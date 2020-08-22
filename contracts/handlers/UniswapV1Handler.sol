// SPDX-License-Identifier: GPL-2.0

pragma solidity ^0.6.8;

import "../libs/SafeMath.sol";
import "../libs/UniswapexUtils.sol";
import "../commons/Order.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IHandler.sol";
import "../interfaces/uniswapV1/IUniswapExchange.sol";
import "../interfaces/uniswapV1/IUniswapFactory.sol";

/// @notice UniswapV1 Handler used to execute an order
contract UniswapV1Handler is IHandler, Order {

    using SafeMath for uint256;

    uint256 private constant never = uint(-1);

    IUniswapFactory public immutable uniswapFactory;

    /**
     * @notice Creates the handler
     * @param _uniswapFactory - Address of the uniswap v1 factory contract
     */
    constructor(IUniswapFactory _uniswapFactory) public {
        uniswapFactory = _uniswapFactory;
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
        uint256 inputAmount = UniswapexUtils.balanceOf(_inputToken, address(this));

        (,address payable relayer, uint256 fee) = abi.decode(_data, (address, address, uint256));

        if (address(_inputToken) == ETH_ADDRESS) {
            // Keep some eth for paying the fee
            uint256 sell = inputAmount.sub(fee);
            bought = _ethToToken(uniswapFactory, _outputToken, sell, msg.sender);
        } else if (address(_outputToken) == ETH_ADDRESS) {
            // Convert
            bought = _tokenToEth(uniswapFactory, _inputToken, inputAmount);
            bought = bought.sub(fee);

            // Send amount bought
            (bool successSender,) = msg.sender.call{value: bought}("");
            require(successSender, "UniswapV1Handler#handle: TRANSFER_ETH_TO_CALLER_FAILED");
        } else {
            // Convert from fromToken to ETH
            uint256 boughtEth = _tokenToEth(uniswapFactory, _inputToken, inputAmount);

            // Convert from ETH to toToken
            bought = _ethToToken(uniswapFactory, _outputToken, boughtEth.sub(fee), msg.sender);
        }

        // Send fee to relayer
        (bool successRelayer,) = relayer.call{value: fee}("");
        require(successRelayer, "UniswapV1Handler#handle: TRANSFER_ETH_TO_RELAYER_FAILED");
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
        (,,uint256 fee) = abi.decode(_data, (address, address, uint256));

        uint256 bought;

        if (address(_inputToken) == ETH_ADDRESS) {
            if (_inputAmount <= fee) {
                return false;
            }

            uint256 sell = _inputAmount.sub(fee);
            bought = _outEthToToken(uniswapFactory, _outputToken, sell);
        } else if (address(_outputToken) == ETH_ADDRESS) {
            bought = _outTokenToEth(uniswapFactory ,_inputToken, _inputAmount);

            if (bought <= fee) {
                return false;
            }

            bought = bought.sub(fee);
        } else {
            uint256 boughtEth =  _outTokenToEth(uniswapFactory, _inputToken, _inputAmount);
            if (boughtEth <= fee) {
                return false;
            }

            bought = _outEthToToken(uniswapFactory, _outputToken, boughtEth.sub(fee));
        }

        return bought >= _minReturn;
    }

    /**
     * @notice Simulate an order execution
     * @param _inputToken - Address of the input token
     * @param _outputToken - Address of the output token
     * @param _inputAmount - uint256 of the input token amount
     * @param _minReturn - uint256 of the min return amount of output token
     * @param _data - Bytes of arbitrary data
     * @return bool - Whether the execution can be handled or not
     * @return uint256 - Amount of output token bought
     */
    function simulate(IERC20 _inputToken,
        IERC20 _outputToken,
        uint256 _inputAmount,
        uint256 _minReturn,
        bytes calldata _data
    ) external view returns (bool, uint256) {
        (,,uint256 fee) = abi.decode(_data, (address, address, uint256));

        uint256 bought;

        if (address(_inputToken) == ETH_ADDRESS) {
            if (_inputAmount <= fee) {
                return (false, 0);
            }

            uint256 sell = _inputAmount.sub(fee);
            bought = _outEthToToken(uniswapFactory, _outputToken, sell);
        } else if (address(_outputToken) == ETH_ADDRESS) {
            bought = _outTokenToEth(uniswapFactory ,_inputToken, _inputAmount);

            if (bought <= fee) {
                return (false, 0);
            }

            bought = bought.sub(fee);
        } else {
            uint256 boughtEth =  _outTokenToEth(uniswapFactory, _inputToken, _inputAmount);
            if (boughtEth <= fee) {
                return (false, 0);
            }

            bought = _outEthToToken(uniswapFactory, _outputToken, boughtEth.sub(fee));
        }

        return (bought >= _minReturn, bought);
    }

    /**
     * @notice Trade ETH to token
     * @param _uniswapFactory - Address of uniswap v1 factory
     * @param _token - Address of the output token
     * @param _amount - uint256 of the ETH amount
     * @param _dest - Address of the trade recipient
     * @return bought - Amount of output token bought
     */
    function _ethToToken(
        IUniswapFactory _uniswapFactory,
        IERC20 _token,
        uint256 _amount,
        address _dest
    ) private returns (uint256) {
        IUniswapExchange uniswap = _uniswapFactory.getExchange(address(_token));

        return uniswap.ethToTokenTransferInput{value: _amount}(1, never, _dest);
    }

    /**
     * @notice Trade token to ETH
     * @param _uniswapFactory - Address of uniswap v1 factory
     * @param _token - Address of the input token
     * @param _amount - uint256 of the input token amount
     * @return bought - Amount of ETH bought
     */
    function _tokenToEth(
        IUniswapFactory _uniswapFactory,
        IERC20 _token,
        uint256 _amount
    ) private returns (uint256) {
        IUniswapExchange uniswap = _uniswapFactory.getExchange(address(_token));
        require(address(uniswap) != address(0), "UniswapV1Handler#_tokenToEth: EXCHANGE_DOES_NOT_EXIST");

        // Check if previous allowance is enough and approve Uniswap if not
        uint256 prevAllowance = _token.allowance(address(this), address(uniswap));
        if (prevAllowance < _amount) {
            if (prevAllowance != 0) {
                _token.approve(address(uniswap), 0);
            }

            _token.approve(address(uniswap), uint(-1));
        }

        // Execute the trade
        return uniswap.tokenToEthSwapInput(_amount, 1, never);
    }

    /**
     * @notice Simulate a ETH to token trade
     * @param _uniswapFactory - Address of uniswap v1 factory
     * @param _token - Address of the output token
     * @param _amount - uint256 of the ETH amount
     * @return bought - Amount of output token bought
     */
    function _outEthToToken(IUniswapFactory _uniswapFactory, IERC20 _token, uint256 _amount) private view returns (uint256) {
        return _uniswapFactory.getExchange(address(_token)).getEthToTokenInputPrice(_amount);
    }

    /**
     * @notice Simulate a token to ETH trade
     * @param _uniswapFactory - Address of uniswap v1 factory
     * @param _token - Address of the input token
     * @param _amount - uint256 of the input token amount
     * @return bought - Amount of ETH bought
     */
    function _outTokenToEth(IUniswapFactory _uniswapFactory, IERC20 _token, uint256 _amount) private view returns (uint256) {
        return _uniswapFactory.getExchange(address(_token)).getTokenToEthInputPrice(_amount);
    }
}