// SPDX-License-Identifier: GPL-2.0

pragma solidity ^0.6.8;

import "./IERC20.sol";


interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint wad) external;
}
