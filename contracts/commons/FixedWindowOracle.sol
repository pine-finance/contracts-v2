// SPDX-License-Identifier: GPL-2.0

pragma solidity ^0.6.8;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';


// fixed window oracle that recomputes the average price for the entire period once every period
// note that the price average is only guaranteed to be over at least 1 period, but may be over a longer period
contract FixedWindowOracle {
    using FixedPoint for *;

    uint public constant MAX_EXTRAPOLATE = 365 days * 20;
    uint public constant PERIOD = 2 minutes;

    address public immutable FACTORY;

    struct Last {
        uint price0Cumulative;
        uint price1Cumulative;
    }

    struct Avg {
        uint32 blockTimestampLast;
        FixedPoint.uq112x112 price0Average;
        FixedPoint.uq112x112 price1Average;
    }

    mapping(address => Last) internal pairLast;
    mapping(address => Avg) internal pairAvg;

    constructor(address _factory) public {
        FACTORY = _factory;
    }

    // helper function that returns the current block timestamp within the range of uint32, i.e. [0, 2**32 - 1]
    function currentBlockTimestamp() internal view returns (uint32) {
        return uint32(block.timestamp % 2 ** 32);
    }

    // produces the cumulative price using counterfactuals to save gas and avoid a call to sync.
    function currentCumulativePrices(
        address pair
    ) internal view returns (uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp) {
        blockTimestamp = currentBlockTimestamp();
        price0Cumulative = IUniswapV2Pair(pair).price0CumulativeLast();
        price1Cumulative = IUniswapV2Pair(pair).price1CumulativeLast();

        // if time has elapsed since the last update on the pair, mock the accumulated price values
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(pair).getReserves();
        if (blockTimestampLast != blockTimestamp) {
            // subtraction overflow is desired
            uint32 timeElapsed = blockTimestamp - blockTimestampLast;
            // addition overflow is desired
            // counterfactual
            price0Cumulative += uint(FixedPoint.fraction(reserve1, reserve0)._x) * timeElapsed;
            // counterfactual
            price1Cumulative += uint(FixedPoint.fraction(reserve0, reserve1)._x) * timeElapsed;
        }
    }

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address _tokenA, address _tokenB) internal pure returns (address token0, address token1) {
        require(_tokenA != _tokenB, 'FixedWindowOracle: IDENTICAL_ADDRESSES');
        (token0, token1) = _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);
        require(token0 != address(0), 'FixedWindowOracle: ZERO_ADDRESS');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address _tokenA, address _tokenB) internal view returns (address pair) {
        (address token0, address token1) = sortTokens(_tokenA, _tokenB);
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                FACTORY,
                keccak256(abi.encodePacked(token0, token1)),
                hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f' // init code hash
            ))));
    }

    function _update(address _pair) internal returns (Avg memory, uint256) {
        Avg memory avg = pairAvg[_pair];
        uint32 blockTimestamp = currentBlockTimestamp();

        if (avg.blockTimestampLast == 0) {
            {
                (
                    uint price0Cumulative,
                    uint price1Cumulative,
                    uint32 priceTimestamp
                ) = currentCumulativePrices(_pair);

                Last memory last;
                last.price0Cumulative = price0Cumulative;
                last.price1Cumulative = price1Cumulative;

                uint256 reserve0; uint256 reserve1;
                (reserve0, reserve1, avg.blockTimestampLast) = IUniswapV2Pair(_pair).getReserves();
                // ensure that there's liquidity in the pair
                require(reserve0 != 0 && reserve1 != 0, 'FixedWindowOracle: NO_RESERVES');

                uint32 virtualDelta = blockTimestamp - priceTimestamp;
                uint32 timeElapsed = 0;

                if (virtualDelta >= PERIOD && virtualDelta < MAX_EXTRAPOLATE) {
                    // Get current reserves
                    // we can extrapolate to whole period, becase it hasn't been any trades
                    avg.price0Average = FixedPoint.fraction(uint112(reserve1), uint112(reserve0));
                    avg.price1Average = FixedPoint.fraction(uint112(reserve0), uint112(reserve1));
                    timeElapsed = uint32(PERIOD);
                }

                pairAvg[_pair] = avg;
                pairLast[_pair] = last;

                return (avg, timeElapsed);
            }
        }

        uint32 timeElapsed = blockTimestamp - avg.blockTimestampLast; // overflow is desired

        // ensure that at least one full period has passed since the last update
        if (timeElapsed >= PERIOD) {
            {
                (
                    uint price0Cumulative,
                    uint price1Cumulative,
                    uint32 priceTimestamp
                ) = currentCumulativePrices(_pair);

                Last memory last = pairLast[_pair];

                // Try to do a virtual sample, if no trade has been made for at least a PERIOD
                // we can assume that the current rate is the same as the previus one, extrapolate a point
                // and return the average on a single call
                uint32 virtualDelta = blockTimestamp - priceTimestamp;
                if (virtualDelta >= PERIOD && virtualDelta < MAX_EXTRAPOLATE) {
                    // Get current reserves
                    // we can extrapolate to whole period, becase it hasn't been any trades
                    (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(_pair).getReserves();
                    avg.price0Average = FixedPoint.fraction(reserve1, reserve0);
                    avg.price1Average = FixedPoint.fraction(reserve0, reserve1);
                    timeElapsed = uint32(PERIOD);
                } else {
                    // overflow is desired, casting never truncates
                    // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
                    avg.price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - last.price0Cumulative) / timeElapsed));
                    avg.price1Average = FixedPoint.uq112x112(uint224((price1Cumulative - last.price1Cumulative) / timeElapsed));
                }

                // Update cumulative while we are at it
                last.price0Cumulative = price0Cumulative;
                last.price1Cumulative = price1Cumulative;
                avg.blockTimestampLast = priceTimestamp;

                // Store latest values
                pairLast[_pair] = last;
                pairAvg[_pair] = avg;
            }
        }

        return (avg, timeElapsed);
    }

    function update(address _tokenA, address _tokenB) external {
        address pair = pairFor(_tokenA, _tokenB);
        _update(pair);
    }

    // note this will always return 0 before update has been called successfully for the first time.
    function consult(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) external returns (
        uint256 delta,
        uint256 amountOut
    ) {
        Avg memory avg;

        (avg, delta) = _update(pairFor(_tokenIn, _tokenOut));
        (address token0, address token1) = sortTokens(_tokenIn, _tokenOut);

        if (_tokenIn == token0) {
            amountOut = avg.price0Average.mul(_amountIn).decode144();
        } else {
            require(_tokenIn == token1, 'FixedWindowOracle: INVALID_TOKEN');
            amountOut = avg.price1Average.mul(_amountIn).decode144();
        }
    }

    // note this will always return 0 before update has been called successfully for the first time.
    function read(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) external view returns (
        uint256 delta,
        uint256 amountOut
    ) {
        Avg memory avg = pairAvg[pairFor(_tokenIn, _tokenOut)];
        (address token0, address token1) = sortTokens(_tokenIn, _tokenOut);
        delta = currentBlockTimestamp() - avg.blockTimestampLast; // overflow is desired

        if (_tokenIn == token0) {
            amountOut = avg.price0Average.mul(_amountIn).decode144();
        } else {
            require(_tokenIn == token1, 'FixedWindowOracle: INVALID_TOKEN');
            amountOut = avg.price1Average.mul(_amountIn).decode144();
        }
    }
}
