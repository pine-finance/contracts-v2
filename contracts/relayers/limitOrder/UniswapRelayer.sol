// SPDX-License-Identifier: GPL-2.0

pragma solidity ^0.6.8;

import "../../libs/SafeMath.sol";
import "../../commons/Order.sol";
import "../../interfaces/IERC20.sol";
import "../../interfaces/IRelayer.sol";
import "../../interfaces/uniswapV1/UniswapExchange.sol";
import "../../interfaces/uniswapV1/UniswapFactory.sol";


contract UniswapRelayer is IRelayer, Order {

    using SafeMath for uint256;

    uint256 private constant never = uint(-1);

    UniswapFactory public uniswapFactory;

    constructor(UniswapFactory _uniswapFactory) public {
        uniswapFactory = _uniswapFactory;
    }

    receive() external override payable { }

    function execute(
        IERC20 _inputToken,
        uint256 _inputAmount,
        address payable _owner,
        bytes calldata _data,
        bytes calldata _auxData
    ) external payable override returns (uint256 bought) {
         (
            IERC20 outputToken,
            uint256 minReturn,
            uint256 fee
        ) = abi.decode(
            _data,
            (
                IERC20,
                uint256,
                uint256
            )
        );

         (,address payable relayer) = abi.decode(_auxData, (address, address));

         if (address(_inputToken) == ETH_ADDRESS) {
            // Keep some eth for paying the fee
            uint256 sell = _inputAmount.sub(fee);
            bought = _ethToToken(uniswapFactory, outputToken, sell, msg.sender);
            relayer.transfer(fee);
        } else if (address(outputToken) == ETH_ADDRESS) {
            // Convert
            bought = _tokenToEth(uniswapFactory, _inputToken, _inputAmount, address(this));
            bought = bought.sub(fee);

            // Send fee and amount bought
            relayer.transfer(fee);
            msg.sender.transfer(bought);
        } else {
            // Convert from fromToken to ETH
            uint256 boughtEth = _tokenToEth(uniswapFactory, _inputToken, _inputAmount, address(this));
            relayer.transfer(fee);

            // Convert from ETH to toToken
            bought = _ethToToken(uniswapFactory, outputToken, boughtEth.sub(fee), msg.sender);
        }
    }

    function canExecute(
        IERC20 _inputToken,
        uint256 _inputAmount,
        bytes calldata _data,
        bytes calldata _auxData
    ) external override view returns (bool) {
        (IERC20 outputToken, uint256 minReturn, uint256 fee) = abi.decode(
            _data,
            (
                IERC20,
                uint256,
                uint256
            )
        );

        uint256 bought;

        if (address(_inputToken) == ETH_ADDRESS) {
            if (_inputAmount <= fee) {
                return false;
            }

            uint256 sell = _inputAmount.sub(fee);
            bought = uniswapFactory.getExchange(address(outputToken)).getEthToTokenInputPrice(sell);
        } else if (address(outputToken) == ETH_ADDRESS) {
            bought = uniswapFactory.getExchange(address(_inputToken)).getTokenToEthInputPrice(_inputAmount);
            if (bought <= fee) {
                return false;
            }

            bought = bought.sub(fee);
        } else {
            uint256 boughtEth = uniswapFactory.getExchange(address(_inputToken)).getTokenToEthInputPrice(_inputAmount);
            if (boughtEth <= fee) {
                return false;
            }

            bought = uniswapFactory.getExchange(address(outputToken)).getEthToTokenInputPrice(boughtEth.sub(fee));
        }

        return bought >= minReturn;
    }

     function _ethToToken(
        UniswapFactory _uniswapFactory,
        IERC20 _token,
        uint256 _amount,
        address _dest
    ) private returns (uint256) {
        UniswapExchange uniswap = _uniswapFactory.getExchange(address(_token));

        if (_dest != address(this)) {
            return uniswap.ethToTokenTransferInput{value: _amount}(1, never, _dest);
        } else {
            return uniswap.ethToTokenSwapInput{value: _amount}(1, never);
        }
    }

    function _tokenToEth(
        UniswapFactory _uniswapFactory,
        IERC20 _token,
        uint256 _amount,
        address _dest
    ) private returns (uint256) {
        UniswapExchange uniswap = _uniswapFactory.getExchange(address(_token));
        require(address(uniswap) != address(0), "The exchange should exist");

        // Check if previous allowance is enough and approve Uniswap if not
        uint256 prevAllowance = _token.allowance(address(this), address(uniswap));
        if (prevAllowance < _amount) {
            if (prevAllowance != 0) {
                _token.approve(address(uniswap), 0);
            }

            _token.approve(address(uniswap), uint(-1));
        }

        // Execute the trade
        if (_dest != address(this)) {
            return uniswap.tokenToEthTransferInput(_amount, 1, never, _dest);
        } else {
            return uniswap.tokenToEthSwapInput(_amount, 1, never);
        }
    }

}