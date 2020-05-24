// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.6.8;


interface IModule {
    function execute(bytes calldata _data) external;
    function canExecute(bytes calldata _data) external view returns (bool);
}
