// SPDX-License-Identifier: GPL-2.0

pragma solidity ^0.6.8;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

import "../../interfaces/IWETH.sol";
import "../../interfaces/IStopLossHandler.sol";
import "../../utils/UniswapUtils.sol";
import "../../utils/UniswapExUtils.sol";
import "../../libs/SafeMath.sol";
import "../../libs/SafeERC20.sol";


contract Uniswap2Handler is IStopLossHandler {
    using SafeMath for uint256;

    IWETH public immutable WETH;
    address public immutable FACTORY;

    constructor(address _factory, IWETH _weth) public {
        FACTORY = _factory;
        WETH = _weth;
    }

    receive() external payable {
        require(msg.sender != tx.origin, "Uniswap2Handler#receive: REJECTED");
    }

    function _swap(address _from, address _to, uint256 _val, address _ben) internal returns (uint256 bought) {
        // Get uniswap trading pair
        (address token0, address token1) = UniswapUtils.sortTokens(_from, _to);
        IUniswapV2Pair pair = IUniswapV2Pair(UniswapUtils.pairForSorted(FACTORY, token0, token1));

        // Send tokens to uniswap pair
        require(SafeERC20.transfer(IERC20(_from), address(pair), _val), "Uniswap2Handler#_swap: ERROR_SENDING_TOKENS");

        // Compute limit for uniswap trade
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 limit = uint(reserve0).mul(reserve1).mul(1000000);

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

    function handle(
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256,
        uint256,
        bytes calldata _data
    ) external override {
        address fromToken = address(_fromToken);
        address toToken = address(_toToken);

        // Load real initial balance, don't trust provided value
        uint256 amount = UniswapExUtils.balanceOf(IERC20(fromToken), address(this));

        // Decode extra data
        (address recipient, uint256 fee) = abi.decode(_data, (address, uint256));

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
            _swap(fromToken, toToken, amount, msg.sender);
        } else if (toToken == address(WETH) || toToken == UniswapExUtils.ETH_ADDRESS) {
            // Swap fromToken -> WETH
            uint256 bought = _swap(fromToken, address(WETH), amount, address(this));

            // Convert from WETH to ETH if necessary
            if (address(fromToken) == UniswapExUtils.ETH_ADDRESS) {
                WETH.withdraw(bought);
            } else {
                WETH.withdraw(fee);
            }

            // Send fee
            recipient.call{ value: fee }("");

            // Transfer to sender
            UniswapExUtils.transfer(IERC20(toToken), msg.sender, bought.sub(fee));
        } else {
            // Swap fromToken -> WETH -> toToken
            //  - fromToken -> WETH
            uint256 bought = _swap(fromToken, address(WETH), amount, address(this));

            // Send fee
            WETH.withdraw(fee);
            recipient.call{ value: fee }("");

            // - WETH -> toToken
            _swap(address(WETH), toToken, bought.sub(fee), msg.sender);
        }
    }
}
