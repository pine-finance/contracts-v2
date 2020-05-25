// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.6.8;

import "../interfaces/IERC20.sol";

interface IModule {
    receive() external payable;

    function execute(
        IERC20 _inputToken,
        uint256 _inputAmount,
        address payable _owner,
        bytes calldata _data,
        bytes calldata _auxData
    ) external returns (uint256 bought);

    function canExecute(
        IERC20 _inputToken,
        uint256 _inputAmount,
        bytes calldata _data,
        bytes calldata _auxData
    ) external view returns (bool);
}
