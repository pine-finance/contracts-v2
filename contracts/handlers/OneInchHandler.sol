// SPDX-License-Identifier: GPL-2.0

pragma solidity ^0.6.8;

import "../libs/SafeMath.sol";
import "../libs/PineUtils.sol";
import "../commons/Order.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IHandler.sol";

/// @notice UniswapV1 Handler used to execute an order

interface IOneSplitWrapper {
    function swap(
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata distribution,
        uint256 flags
    ) external payable;
}

contract OneinchHandler is IHandler, Order {
    using SafeMath for uint256;

    IOneSplitWrapper public immutable oneSplitWrapper;

    uint256 private constant never = uint(-1);

    /**
     * @notice Creates the handler
     * @param _oneSplitWrapper - Address of oneSplitWrapper
     */
    constructor(IOneSplitWrapper _oneSplitWrapper) public {
        oneSplitWrapper = _oneSplitWrapper;
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
        uint256 inputAmount = PineUtils.balanceOf(_inputToken, address(this));
        address inputToken = address(_inputToken);
        address outputToken = address(_outputToken);

        (,address payable relayer, uint256 fee, uint256 flag, uint256[] memory distributionsA, uint256[] memory distributionsB) =
             abi.decode(_data, (address, address, uint256, uint256, uint256[], uint256[]));

        if (inputToken == ETH_ADDRESS) {
            // Keep some eth for paying the fee
            uint256 sell = inputAmount.sub(fee);
            bought = _swap(inputToken, outputToken, sell, msg.sender, distributionsA, flag);
        } else if (outputToken == ETH_ADDRESS) {
            // Convert
            bought = _swap(inputToken, outputToken, inputAmount, address(this), distributionsA, flag);
            bought = bought.sub(fee);

            // Send amount bought
            (bool successSender,) = msg.sender.call{value: bought}("");
            require(successSender, "UniswapV1Handler#handle: TRANSFER_ETH_TO_CALLER_FAILED");
        } else {
            // Convert from fromToken to ETH
            uint256 boughtEth = _swap(inputToken, ETH_ADDRESS, inputAmount, address(this), distributionsA, flag);

            // Convert from ETH to toToken
            bought = _swap(ETH_ADDRESS, outputToken, boughtEth.sub(fee), msg.sender, distributionsB, flag);
        }

        // Send fee to relayer
        (bool successRelayer,) = relayer.call{value: fee}("");
        require(successRelayer, "UniswapV1Handler#handle: TRANSFER_ETH_TO_RELAYER_FAILED");
    }

    /**
     * @notice Check whether can handle an order execution
     * @return bool - Whether the execution can be handled or not
     */
    function canHandle(
        IERC20,
        IERC20,
        uint256,
        uint256,
        bytes calldata
    ) external override view returns (bool) {
       return false;
    }

    /**
     * @notice Swap input token to output token
     * @param _inputToken - Address of the input token
     * @param _outputToken - Address of the output token
     * @param _inputAmount - uint256 of the input token amount
     * @param _recipient - Address of the recipient
     * @param _distributions - Array of weights for volume distribution
     * @param _flag - flags
     * @return bought - Amount of output token bought
     */
    function _swap(
        address _inputToken,
        address _outputToken,
        uint256 _inputAmount,
        address _recipient,
        uint256[] memory _distributions,
        uint256 _flag
    ) internal returns (uint256 bought) {
        // Check if previous allowance is enough and approve the pool if not
        IERC20 inputToken = IERC20(_inputToken);
        uint256 value = 0;

        if (_inputToken == ETH_ADDRESS) {
            value = _inputAmount;
        } else {
            uint256 prevAllowance = inputToken.allowance(address(this), address(oneSplitWrapper));
            if (prevAllowance < _inputAmount) {
                if (prevAllowance != 0) {
                    inputToken.approve(address(oneSplitWrapper), 0);
                }

                inputToken.approve(address(oneSplitWrapper), uint(-1));
            }
        }

        oneSplitWrapper.swap{ value: value }(
            _inputToken,
            _outputToken,
            _inputAmount,
            0,
            _distributions,
            _flag
        );

        bought = PineUtils.balanceOf(IERC20(_outputToken), address(this));

        if (_recipient != address(this)) {
            PineUtils.transfer(IERC20(_outputToken), _recipient, bought);
        }
    }
}