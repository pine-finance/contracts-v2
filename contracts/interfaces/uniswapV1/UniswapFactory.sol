// SPDX-License-Identifier: GPL-2.0

pragma solidity ^0.6.8;

import "../../interfaces/IERC20.sol";
import "./UniswapExchange.sol";


abstract contract UniswapFactory {
    // Public Variables
    address public exchangeTemplate;
    uint256 public tokenCount;
    // Create Exchange
    function createExchange(address token) external virtual returns (address exchange);
    // Get Exchange and Token Info
    function getExchange(address token) external virtual view returns (UniswapExchange exchange);
    function getToken(address exchange) external virtual view returns (IERC20 token);
    function getTokenWithId(uint256 tokenId) external virtual view returns (address token);
    // Never use
    function initializeFactory(address template) external virtual;
}
