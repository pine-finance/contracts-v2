// SPDX-License-Identifier: GPL-2.0

pragma solidity ^0.6.8;

import "../libs/SafeMath.sol";


interface Fac {
     function getPair(address tokenA, address tokenB) external view returns (address pair);
}

library UniswapUtils {
    using SafeMath for uint256;

    // helper function that returns the current block timestamp within the range of uint32, i.e. [0, 2**32 - 1]
    function currentBlockTimestamp() internal view returns (uint32) {
        return uint32(block.timestamp % 2 ** 32);
    }

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address _tokenA, address _tokenB) internal pure returns (address token0, address token1) {
        require(_tokenA != _tokenB, 'UniswapUtils#sortTokens: IDENTICAL_ADDRESSES');
        (token0, token1) = _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);
        require(token0 != address(0), 'UniswapUtils#sortTokens: ZERO_ADDRESS');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address _factory, address _tokenA, address _tokenB, bytes memory _initCodeHash) internal view returns (address pair) {
        (address token0, address token1) = sortTokens(_tokenA, _tokenB);
       //  pair = Fac(_factory).getPair(token0, token1);
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                _factory,
                keccak256(abi.encodePacked(token0, token1)),
                _initCodeHash // init code hash
            ))));
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairForSorted(address _factory, address _token0, address _token1, bytes memory _initCodeHash) internal view returns (address pair) {
        //pair = Fac(_factory).getPair(_token0, _token1);
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                _factory,
                keccak256(abi.encodePacked(_token0, _token1)),
                _initCodeHash // init code hash
            ))));
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint _amountIn, uint _reserveIn, uint _reserveOut) internal pure returns (uint amountOut) {
        require(_amountIn > 0, 'UniswapUtils#getAmountOut: INSUFFICIENT_INPUT_AMOUNT');
        require(_reserveIn > 0 && _reserveOut > 0, 'UniswapUtils#getAmountOut: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = _amountIn.mul(997);
        uint numerator = amountInWithFee.mul(_reserveOut);
        uint denominator = _reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }
}