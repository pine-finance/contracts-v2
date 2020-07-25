// SPDX-License-Identifier: GPL-2.0

pragma solidity ^0.6.8;

import "../../interfaces/IWETH.sol";
import "../../interfaces/IHandler.sol";
import "../../interfaces/uniswapV2/IUniswapV2Pair.sol";
import "../../libs/UniswapUtils.sol";
import "../../libs/UniswapExUtils.sol";
import "../../libs/SafeMath.sol";
import "../../libs/SafeERC20.sol";


contract UniswapV2Handler is IHandler {
    using SafeMath for uint256;

    IWETH public immutable WETH;
    address public immutable FACTORY;

    constructor(address _factory, IWETH _weth) public {
        FACTORY = _factory;
        WETH = _weth;
    }

    function handle(
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256,
        uint256,
        bytes calldata _data
    ) external payable override returns (uint256) {
        address fromToken = address(_fromToken);
        address toToken = address(_toToken);

        // Load real initial balance, don't trust provided value
        uint256 amount = UniswapExUtils.balanceOf(IERC20(fromToken), address(this));

        // Decode extra data
        (,address recipient, uint256 fee) = abi.decode(_data, (address, address, uint256));

        if (fromToken == address(WETH) || fromToken == UniswapExUtils.ETH_ADDRESS) {
            // Swap WETH -> toToken
            amount = amount.sub(fee);

            // Convert from ETH to WETH if necessary
            if (fromToken == UniswapExUtils.ETH_ADDRESS) {
                WETH.deposit{ value: amount }();
                fromToken = address(WETH);
            } else {
                WETH.withdraw(fee);
            }

            // Send fee
            recipient.call{ value: fee }("");

            // Trade
            return _swap(fromToken, toToken, amount, msg.sender);
        } else if (toToken == address(WETH) || toToken == UniswapExUtils.ETH_ADDRESS) {
            // Swap fromToken -> WETH
            uint256 bought = _swap(fromToken, address(WETH), amount, address(this));

            // Convert from WETH to ETH if necessary
            if (address(toToken) == UniswapExUtils.ETH_ADDRESS) {
                WETH.withdraw(bought);
            } else {
                WETH.withdraw(fee);
            }

            // Send fee
            recipient.call{ value: fee }("");

            // Transfer to sender
            bought = bought.sub(fee);
            UniswapExUtils.transfer(IERC20(toToken), msg.sender, bought);
            return bought;
        } else {
            // Swap fromToken -> WETH -> toToken
            //  - fromToken -> WETH
            uint256 bought = _swap(fromToken, address(WETH), amount, address(this));

            // Send fee
            WETH.withdraw(fee);
            recipient.call{ value: fee }("");

            // - WETH -> toToken
            return _swap(address(WETH), toToken, bought.sub(fee), msg.sender);
        }
    }

    function canHandle(
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _amount,
        uint256 _minReturn,
        bytes calldata _data
    ) external override view returns (bool) {
        address fromToken = address(_fromToken);
        address toToken = address(_toToken);

        // Decode extra data
        (,, uint256 fee) = abi.decode(_data, (address, address, uint256));

        if (fromToken == address(WETH) || fromToken == UniswapExUtils.ETH_ADDRESS) {
            if (_amount < fee) return false;
            return _estimate(address(WETH), toToken, _amount.sub(fee)) >= _minReturn;
        } else if (toToken == address(WETH) || toToken == UniswapExUtils.ETH_ADDRESS) {
            uint256 bought = _estimate(fromToken, address(WETH), _amount);
            if (bought < fee) return false;
            return bought.sub(fee) >= _minReturn;
        } else {
            uint256 bought = _estimate(fromToken, address(WETH), _amount);
            if (bought < fee) return false;
            return _estimate(address(WETH), toToken, bought.sub(fee)) >= _minReturn;
        }
    }

    receive() external override payable {
        require(msg.sender != tx.origin, "Uniswap2Handler#receive: REJECTED");
    }

    function _estimate(address _from, address _to, uint256 _val) internal view returns (uint256 bought) {
        // Get uniswap trading pair
        (address token0, address token1) = UniswapUtils.sortTokens(_from, _to);
        IUniswapV2Pair pair = IUniswapV2Pair(UniswapUtils.pairForSorted(FACTORY, token0, token1));

        // Compute limit for uniswap trade
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        // Optimal amounts for uniswap trade
        uint256 reserveIn; uint256 reserveOut;
        if (_from == token0) {
            reserveIn = reserve0;
            reserveOut = reserve1;
        } else {
            reserveIn = reserve1;
            reserveOut = reserve0;
        }

        bought = UniswapUtils.getAmountOut(_val, reserveIn, reserveOut);
    }

    function _swap(address _from, address _to, uint256 _val, address _ben) internal returns (uint256 bought) {
        // Get uniswap trading pair
        (address token0, address token1) = UniswapUtils.sortTokens(_from, _to);
        IUniswapV2Pair pair = IUniswapV2Pair(UniswapUtils.pairForSorted(FACTORY, token0, token1));

        // Send tokens to uniswap pair
        require(SafeERC20.transfer(IERC20(_from), address(pair), _val), "Uniswap2Handler#_swap: ERROR_SENDING_TOKENS");

        // Get current reserves
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        // Optimal amounts for uniswap trade
        {
            uint256 reserveIn; uint256 reserveOut;
            if (_from == token0) {
                reserveIn = reserve0;
                reserveOut = reserve1;
            } else {
                reserveIn = reserve1;
                reserveOut = reserve0;
            }
            bought = UniswapUtils.getAmountOut(_val, reserveIn, reserveOut);
        }

        // Determine if output amount is token1 or token0
        uint256 amount1Out; uint256 amount0Out;
        if (_from == token0) {
            amount1Out = bought;
        } else {
            amount0Out = bought;
        }

        // Execute swap
        pair.swap(amount0Out, amount1Out, _ben, bytes(""));
    }
}