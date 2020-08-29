// SPDX-License-Identifier: GPL-2.0

pragma solidity ^0.6.8;

import "../../interfaces/IERC20.sol";
import "../../interfaces/IHandler.sol";

/// @notice Hacker Handler used for testing
contract HackerHandler is IHandler {

    uint256 private constant never = uint(-1);

    constructor() public {
    }

    receive() external override payable {
    }

    /// @notice don't buy anything
    function handle(
        IERC20,
        IERC20,
        uint256,
        uint256 _minReturn,
        bytes calldata
    ) external payable override returns (uint256 bought) {
        return _minReturn;
    }

    /// @notice Check whether can handle an order execution
    function canHandle(
        IERC20,
        IERC20,
        uint256,
        uint256,
        bytes calldata
    ) external override view returns (bool) {
        return true;
    }
}

contract HackerNOETHHandler is IHandler {

    uint256 private constant never = uint(-1);

    constructor() public {
    }

    receive() external override payable {
        revert("NO_SEND_ETH_PLEASE");
    }

    /// @notice don't buy anything
    function handle(
        IERC20,
        IERC20,
        uint256,
        uint256 _minReturn,
        bytes calldata
    ) external payable override returns (uint256 bought) {
        return _minReturn;
    }

    /// @notice Check whether can handle an order execution
    function canHandle(
        IERC20,
        IERC20,
        uint256,
        uint256,
        bytes calldata
    ) external override view returns (bool) {
        return true;
    }
}