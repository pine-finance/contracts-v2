// SPDX-License-Identifier: GPL-2.0

pragma solidity ^0.6.8;

import "../libs/SafeMath.sol";
import "../commons/Order.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IHandler.sol";
import "../interfaces/uniswapV1/UniswapExchange.sol";
import "../interfaces/uniswapV1/UniswapFactory.sol";
import "../interfaces/uniswapV2/IUniswapV2Router.sol";


contract UniswapV1Handler is IHandler, Order {

    using SafeMath for uint256;

    uint256 private constant never = uint(-1);

    UniswapFactory public immutable uniswapFactory;

    constructor(UniswapFactory _uniswapFactory) public {
        uniswapFactory = _uniswapFactory;
    }

    receive() external override payable {
        require(msg.sender != tx.origin, "UniswapV1Handler#receive: NO_SEND_ETH_PLEASE");
    }

    function handle(
        IERC20 _inputToken,
        IERC20 _outputToken,
        uint256 _inputAmount,
        uint256,
        bytes calldata _data
    ) external payable override returns (uint256 bought) {
        (,address payable relayer, uint256 fee) = abi.decode(_data, (address, address, uint256));

         if (address(_inputToken) == ETH_ADDRESS) {
            // Keep some eth for paying the fee
            uint256 sell = _inputAmount.sub(fee);
            bought = _ethToToken(uniswapFactory, _outputToken, sell, msg.sender);
        } else if (address(_outputToken) == ETH_ADDRESS) {
            // Convert
            bought = _tokenToEth(uniswapFactory, _inputToken, _inputAmount);
            bought = bought.sub(fee);

            // Send amount bought
            (bool successSender,) = msg.sender.call{value: bought}("");
            require(successSender, "UniswapV1Handler#handle: TRANSFER_ETH_TO_CALLER_FAILED");
        } else {
            // Convert from fromToken to ETH
            uint256 boughtEth = _tokenToEth(uniswapFactory, _inputToken, _inputAmount);

            // Convert from ETH to toToken
            bought = _ethToToken(uniswapFactory, _outputToken, boughtEth.sub(fee), msg.sender);
        }

        // Send fee to relayer
        (bool successRelayer,) = relayer.call{value: fee}("");
        require(successRelayer, "UniswapV1Handler#handle: TRANSFER_ETH_TO_RELAYER_FAILED");
    }

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
    * @dev Simulate and return bought amount
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

    function _ethToToken(
        UniswapFactory _uniswapFactory,
        IERC20 _token,
        uint256 _amount,
        address _dest
    ) private returns (uint256) {
        UniswapExchange uniswap = _uniswapFactory.getExchange(address(_token));

        return uniswap.ethToTokenTransferInput{value: _amount}(1, never, _dest);
    }

    function _tokenToEth(
        UniswapFactory _uniswapFactory,
        IERC20 _token,
        uint256 _amount
    ) private returns (uint256) {
        UniswapExchange uniswap = _uniswapFactory.getExchange(address(_token));
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

    function _outEthToToken(UniswapFactory _uniswapFactory, IERC20 _token, uint256 _amount) private view returns (uint256) {
        return _uniswapFactory.getExchange(address(_token)).getEthToTokenInputPrice(_amount);
    }

    function _outTokenToEth(UniswapFactory _uniswapFactory,IERC20 _token, uint256 _amount) private view returns (uint256) {
        return _uniswapFactory.getExchange(address(_token)).getTokenToEthInputPrice(_amount);
    }
}