// SPDX-License-Identifier: GPL-2.0

pragma solidity ^0.6.8;

import "../libs/SafeMath.sol";


library UniswapUtils {
    using SafeMath for uint256;

    /**
     * @notice Returns the current block timestamp within the range of uint32, i.e. [0, 2**32 - 1]
     * @return uint32 - block timestamp
     */
    function currentBlockTimestamp() internal view returns (uint32) {
        return uint32(block.timestamp % 2 ** 32);
    }

    /**
     * @notice Returns sorted token addresses, used to handle return values from pairs sorted in this order
     * @param _tokenA - Address of the token A
     * @param _tokenB - Address of the token B
     * @return token0 - Address of the lower token
     * @return token1 - Address of the higher token
     */
    function sortTokens(address _tokenA, address _tokenB) internal pure returns (address token0, address token1) {
        require(_tokenA != _tokenB, 'UniswapUtils#sortTokens: IDENTICAL_ADDRESSES');
        (token0, token1) = _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);
        require(token0 != address(0), 'UniswapUtils#sortTokens: ZERO_ADDRESS');
    }

    /**
     * @notice Calculates the CREATE2 address for a pair without making any external calls
     * @param _factory - Address of the uniswapV2 factory contract
     * @param _tokenA - Address of the token A
     * @param _tokenB - Address of the token B
     * @param _initCodeHash - Bytes32 of the uniswap v2 pair contract unit code hash
     * @return pair - Address of the pair
     */
    function pairFor(address _factory, address _tokenA, address _tokenB, bytes32 _initCodeHash) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(_tokenA, _tokenB);
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                _factory,
                keccak256(abi.encodePacked(token0, token1)),
                _initCodeHash // init code hash
            ))));
    }

    /**
     * @notice Calculates the CREATE2 address for a pair without making any external calls
     * @dev Tokens should be in order
     * @param _factory - Address of the uniswapV2 factory contract
     * @param _token0 - Address of the token 0
     * @param _token1 - Address of the token 1
     * @param _initCodeHash - Bytes32 of the uniswap v2 pair contract unit code hash
     * @return pair - Address of the pair
     */
    function pairForSorted(address _factory, address _token0, address _token1, bytes32 _initCodeHash) internal pure returns (address pair) {
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                _factory,
                keccak256(abi.encodePacked(_token0, _token1)),
                _initCodeHash // init code hash
            ))));
    }

    /**
     * @notice Given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
     * @param _amountIn - uint of the input token's amount
     * @param _reserveIn - uint of the input token's reserve
     * @param _reserveOut - uint of the output token's reserve
     * @return amountOut - Maximum output amount
     */
    function getAmountOut(uint _amountIn, uint _reserveIn, uint _reserveOut) internal pure returns (uint amountOut) {
        require(_amountIn > 0, 'UniswapUtils#getAmountOut: INSUFFICIENT_INPUT_AMOUNT');
        require(_reserveIn > 0 && _reserveOut > 0, 'UniswapUtils#getAmountOut: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = _amountIn.mul(997);
        uint numerator = amountInWithFee.mul(_reserveOut);
        uint denominator = _reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }
}