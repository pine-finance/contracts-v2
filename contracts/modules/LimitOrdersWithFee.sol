// SPDX-License-Identifier: GPL-2.0

pragma solidity ^0.6.8;

import "./LimitOrders.sol";


/// @notice Module used to execute limit orders with fee create in the core contract
contract LimitOrdersWithFee is LimitOrders {
    address payable public immutable FEE_RECIPIENT;

    uint256 private constant FEE_AMOUNT = 3;
    uint256 private constant FEE_BASE = 1000;

    constructor(address payable _feeRecipient) public {
        FEE_RECIPIENT = _feeRecipient;
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
    ) external override view returns (bool) {
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
        uint256 fee = _inputAmount.mul(FEE_AMOUNT) / FEE_BASE;
        uint256 inputAmount = _inputAmount.sub(fee);

        return handler.canHandle(
            _inputToken,
            outputToken,
            inputAmount,
            minReturn,
            _auxData
        );
    }

    /**
     * @notice Transfers tokens to a recipient it tries to transfer the requested amount, if it fails it transfers everything
     * @dev This method has been overriden in order to transfer the fixed fee
     * @param _token - Address of the token to transfer
     * @param _to - Address of the recipient
     * @param _amount - Tentative amount to be transfered
     * @return uint256 - The final number of transfered tokens
     */
    function _transferAllBalance(
        IERC20 _token,
        address payable _to,
        uint256 _amount
    ) internal override returns (uint256) {
        // Calculate fee to pay
        uint256 fee = _amount.mul(FEE_AMOUNT) / FEE_BASE;
        require(_transferAmount(_token, FEE_RECIPIENT, fee), "LimitOrdersWithFee#_transferAllBalance: ERROR_SENDING_FEE");

        // Try to transfer requested amount
        return super._transferAllBalance(_token, _to, _amount.sub(fee));
    }
}
