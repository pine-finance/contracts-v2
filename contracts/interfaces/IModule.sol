// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.6.8;

import "../interfaces/IERC20.sol";

interface IModule {
    receive() external payable;

    function execute(
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _amount,
        uint256 _minReturn,
        uint256 _fee,
        address payable _owner,
        address payable _relayer,
        bytes calldata _data
    ) external returns (uint256 bought);

    function canExecute(
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _amount,
        uint256 _minReturn,
        uint256 _fee,
        bytes calldata _data
    ) external view returns (bool);
}
