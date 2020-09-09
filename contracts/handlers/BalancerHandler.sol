// SPDX-License-Identifier: GPL-2.0

pragma solidity ^0.6.8;

import "../libs/SafeMath.sol";
import "../libs/PineUtils.sol";
import "../commons/Order.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IHandler.sol";
import "../interfaces/uniswapV1/IUniswapExchange.sol";
import "../interfaces/uniswapV1/IUniswapFactory.sol";

/// @notice UniswapV1 Handler used to execute an order

interface PoolInterface {
    function swapExactAmountIn(address, uint, address, uint, uint) external returns (uint, uint);
}

contract BalancerHandler is IHandler, Order {
    using SafeMath for uint256;

    IWETH public immutable WETH;

    uint256 private constant never = uint(-1);

    /**
     * @notice Creates the handler
     * @param _weth - Address of WETH contract
     */
    constructor(IWETH _weth) public {
        WETH = _weth;
    }

    /// @notice receive ETH
    receive() external override payable {
        require(msg.sender != tx.origin, "UniswapV1Handler#receive: NO_SEND_ETH_PLEASE");
    }

    /**
     * @notice Handle an order execution
     * @param _inputToken - Address of the input token
     * @param _outputToken - Address of the output token
     * @param _data - Bytes of arbitrary data
     * @return bought - Amount of output token bought
     */
    function handle(
        IERC20 _inputToken,
        IERC20 _outputToken,
        uint256,
        uint256,
        bytes calldata _data
    ) external payable override returns (uint256 bought) {
        // Load real initial balance, don't trust provided value
        uint256 amount = PineUtils.balanceOf(_inputToken, address(this));
        address inputToken = address(_inputToken);
        address outputToken = address(_outputToken);
        address weth = address(WETH);

        (,address payable relayer, uint256 fee, address payable poolA, address payable poolB) =
            abi.decode(_data, (address, address, uint256, address, address));

        if (inputToken == weth || inputToken == PineUtils.ETH_ADDRESS) {
            // Swap WETH -> outputToken
            amount = amount.sub(fee);

            // Convert from ETH to WETH if necessary
            if (inputToken == PineUtils.ETH_ADDRESS) {
                WETH.deposit{ value: amount }();
                inputToken = weth;
            } else {
                WETH.withdraw(fee);
            }

            // Trade
            bought = _swap(poolA, inputToken, outputToken, amount, msg.sender);
        } else if (outputToken == weth || outputToken == PineUtils.ETH_ADDRESS) {
            // Swap inputToken -> WETH
            bought = _swap(poolA, inputToken, weth, amount, address(this));

            // Convert from WETH to ETH if necessary
            if (outputToken == PineUtils.ETH_ADDRESS) {
                WETH.withdraw(bought);
            } else {
                WETH.withdraw(fee);
            }

            // Transfer amount to sender
            bought = bought.sub(fee);
            PineUtils.transfer(IERC20(outputToken), msg.sender, bought);
        } else {
            // Swap inputToken -> WETH -> outputToken
            //  - inputToken -> WETH
            bought = _swap(poolA, inputToken, weth, amount, address(this));

            // Withdraw fee
            WETH.withdraw(fee);

            // - WETH -> outputToken
            bought = _swap(poolB, weth, outputToken, bought.sub(fee), msg.sender);
        }

        // Send fee to relayer
        (bool successRelayer,) = relayer.call{value: fee}("");
        require(successRelayer, "UniswapV2Handler#handle: TRANSFER_ETH_TO_RELAYER_FAILED");
    }

    /**
     * @notice Check whether can handle an order execution
     * @param _inputToken - Address of the input token
     * @param _outputToken - Address of the output token
     * @param _inputAmount - uint256 of the input token amount
     * @param _minReturn - uint256 of the min return amount of output token
     * @param _data - Bytes of arbitrary data
     * @return bool - Whether the execution can be handled or not
     */
    function canHandle(
        IERC20 _inputToken,
        IERC20 _outputToken,
        uint256 _inputAmount,
        uint256 _minReturn,
        bytes calldata _data
    ) external override view returns (bool) {
       return false;
    }

    /**
     * @notice Swap input token to output token
     * @param _inputToken - Address of the input token
     * @param _outputToken - Address of the output token
     * @param _inputAmount - uint256 of the input token amount
     * @param _recipient - Address of the recipient
     * @return bought - Amount of output token bought
     */
    function _swap(
        address _pool,
        address _inputToken,
        address _outputToken,
        uint256 _inputAmount,
        address _recipient
    ) internal returns (uint256 bought) {
        // Check if previous allowance is enough and approve the pool if not
        IERC20 inputToken = IERC20(_inputToken);

        uint256 prevAllowance = inputToken.allowance(address(this), _pool);
        if (prevAllowance < _inputAmount) {
            if (prevAllowance != 0) {
                inputToken.approve(_pool, 0);
            }

            inputToken.approve(_pool, uint(-1));
        }

        (bought,) = PoolInterface(_pool).swapExactAmountIn(
            _inputToken,
            _inputAmount,
            _outputToken,
            never,
            never
        );

        if (_recipient != address(this)) {
            PineUtils.transfer(IERC20(_outputToken), _recipient, bought);
        }
    }
}