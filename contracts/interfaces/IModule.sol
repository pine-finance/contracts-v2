// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.6.8;

import "../interfaces/IERC20.sol";



interface IModule {
    /// @notice receive ETH
    receive() external payable;

    /**
     * @notice Executes an order
     * @param _inputToken - Address of the input token
     * @param _inputAmount - uint256 of the input token amount (order amount)
     * @param _owner - Address of the order's owner
     * @param _data - Bytes of the order's data
     * @param _auxData - Bytes of the auxiliar data used for the handlers to execute the order
     * @return bought - amount of output token bought
     */
    function execute(
        IERC20 _inputToken,
        uint256 _inputAmount,
        address payable _owner,
        bytes calldata _data,
        bytes calldata _auxData
    ) external returns (uint256 bought);

    /**
     * @notice Check whether an order can be executed or not
     * @param _inputToken - Address of the input token
     * @param _inputAmount - uint256 of the input token amount (order amount)
     * @param _data - Bytes of the order's data
     * @param _auxData - Bytes of the auxiliar data used for the handlers to execute the order
     * @return bool - whether the order can be executed or not
     */
    function canExecute(
        IERC20 _inputToken,
        uint256 _inputAmount,
        bytes calldata _data,
        bytes calldata _auxData
    ) external view returns (bool);
}
