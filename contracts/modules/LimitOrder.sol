// SPDX-License-Identifier: GPL-2.0

pragma solidity ^0.6.8;

import "../interfaces/IModule.sol";
import "../interfaces/uniswapV1/UniswapExchange.sol";
import "../interfaces/uniswapV1/UniswapFactory.sol";
import "../commons/Order.sol";
import "../libs/SafeMath.sol";


contract LimitOrder is IModule, Order {
    using SafeMath for uint256;

    uint256 private constant never = uint(-1);

    UniswapFactory public uniswapFactory;

    constructor(UniswapFactory _uniswapFactory) public {
        uniswapFactory = _uniswapFactory;
    }

    receive() external override payable { }

    function execute(
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _amount,
        uint256 _minReturn,
        uint256 _fee,
        address payable _owner,
        address payable _relayer,
        bytes calldata _data
    ) external override returns (uint256 bought){
        if (address(_fromToken) == ETH_ADDRESS) {
            // Keep some eth for paying the fee
            uint256 sell = _amount.sub(_fee);
            bought = _ethToToken(uniswapFactory, _toToken, sell, _owner);
            _relayer.transfer(_fee);
        } else if (address(_toToken) == ETH_ADDRESS) {
            // Convert
            bought = _tokenToEth(uniswapFactory, _fromToken, _amount, address(this));
            bought = bought.sub(_fee);

            // Send fee and amount bought
            _relayer.transfer(_fee);
            _owner.transfer(bought);
        } else {
            // Convert from fromToken to ETH
            uint256 boughtEth = _tokenToEth(uniswapFactory, _fromToken, _amount, address(this));
            _relayer.transfer(_fee);

            // Convert from ETH to toToken
            bought = _ethToToken(uniswapFactory, _toToken, boughtEth.sub(_fee), _owner);
        }

        require(bought >= _minReturn, "Tokens bought are not enough");

        return bought;
    }

    function canExecute(
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _amount,
        uint256 _minReturn,
        uint256 _fee,
        bytes calldata _data
    ) external override view returns (bool) {
        uint256 bought;

        if (address(_fromToken) == ETH_ADDRESS) {
            if (_amount <= _fee) {
                return false;
            }

            uint256 sell = _amount.sub(_fee);
            bought = uniswapFactory.getExchange(address(_toToken)).getEthToTokenInputPrice(sell);
        } else if (address(_toToken) == ETH_ADDRESS) {
            bought = uniswapFactory.getExchange(address(_fromToken)).getTokenToEthInputPrice(_amount);
            if (bought <= _fee) {
                return false;
            }

            bought = bought.sub(_fee);
        } else {
            uint256 boughtEth = uniswapFactory.getExchange(address(_fromToken)).getTokenToEthInputPrice(_amount);
            if (boughtEth <= _fee) {
                return false;
            }

            bought = uniswapFactory.getExchange(address(_toToken)).getEthToTokenInputPrice(boughtEth.sub(_fee));
        }

        return bought >= _minReturn;
    }

    function _ethToToken(
        UniswapFactory _uniswapFactory,
        IERC20 _token,
        uint256 _amount,
        address _dest
    ) private returns (uint256) {
        UniswapExchange uniswap = _uniswapFactory.getExchange(address(_token));

        if (_dest != address(this)) {
            return uniswap.ethToTokenTransferInput.value(_amount)(1, never, _dest);
        } else {
            return uniswap.ethToTokenSwapInput.value(_amount)(1, never);
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