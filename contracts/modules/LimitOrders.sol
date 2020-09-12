// SPDX-License-Identifier: GPL-2.0

pragma solidity ^0.6.8;

import "../interfaces/IModule.sol";
import "../interfaces/IHandler.sol";
import "../commons/Order.sol";
import "../libs/SafeMath.sol";
import "../libs/SafeERC20.sol";
import "../libs/PineUtils.sol";


/// @notice Module used to execute limit orders create in the core contract
contract LimitOrders is IModule, Order {
    using SafeMath for uint256;

    /// @notice receive ETH
    receive() external override payable { }

    /**
     * @notice Executes an order
     * @param _inputToken - Address of the input token
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
    ) external override returns (uint256 bought) {
        (
            IERC20 outputToken,
            uint256 minReturn
        ) = abi.decode(
            _data,
            (
                IERC20,
                uint256
            )
        );

        (IHandler handler) = abi.decode(_auxData, (IHandler));

        // Do not trust on _inputToken, it can mismatch the real balance
        uint256 inputAmount = _transferAllBalance(_inputToken, address(handler), _inputAmount);

        handler.handle(
            _inputToken,
            outputToken,
            inputAmount,
            minReturn,
            _auxData
        );

        bought = PineUtils.balanceOf(outputToken, address(this));
        require(bought >= minReturn, "LimitOrders#execute: INSUFFICIENT_BOUGHT_TOKENS");
        require(_transferAmount(outputToken, _owner, bought), "LimitOrders#execute: ERROR_SENDING_BOUGHT_TOKENS");

        return bought;
    }

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
    ) external override virtual view returns (bool) {
         (
            IERC20 outputToken,
            uint256 minReturn
        ) = abi.decode(
            _data,
            (
                IERC20,
                uint256
            )
        );
        (IHandler handler) = abi.decode(_auxData, (IHandler));

        return handler.canHandle(
            _inputToken,
            outputToken,
            _inputAmount,
            minReturn,
            _auxData
        );
    }

    /**
     * @notice Transfer token or Ether amount to a recipient
     * @param _token - Address of the token
     * @param _to - Address of the recipient
     * @param _amount - uint256 of the amount to be transferred
     */
    function _transferAmount(
        IERC20 _token,
        address payable _to,
        uint256 _amount
    ) internal returns (bool) {
        if (address(_token) == ETH_ADDRESS) {
            (bool success,) = _to.call{value: _amount}("");
            return success;
        } else {
            return SafeERC20.transfer(_token, _to, _amount);
        }
    }

    /**
     * @notice Transfers tokens to a recipient it tries to transfer the requested amount, if it fails it transfers everything
     * @param _token - Address of the token to transfer
     * @param _to - Address of the recipient
     * @param _amount - Tentative amount to be transfered
     * @return uint256 - The final number of transfered tokens
     */
    function _transferAllBalance(
        IERC20 _token,
        address payable _to,
        uint256 _amount
    ) internal virtual returns (uint256) {
        // Try to transfer requested amount
        if (_transferAmount(_token, _to, _amount)) {
            return _amount;
        }

        // Fallback to read actual current balance
        uint256 balance = PineUtils.balanceOf(_token, address(this));
        require(_transferAmount(_token, _to, balance), "LimitOrders#_transferAllBalance: ERROR_SENDING_TOKENS");
        return balance;
    }
}
