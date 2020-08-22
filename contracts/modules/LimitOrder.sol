// SPDX-License-Identifier: GPL-2.0

pragma solidity ^0.6.8;

import "../interfaces/IModule.sol";
import "../interfaces/IHandler.sol";
import "../commons/Order.sol";
import "../libs/SafeMath.sol";


/// @notice Module used to execute limit orders create in the core contract
contract LimitOrder is IModule, Order {
    using SafeMath for uint256;

    /// @notice receive ETH
    receive() external override payable { }

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

        _transferAmount(_inputToken, address(handler), _inputAmount);

        handler.handle(
            _inputToken,
            outputToken,
            _inputAmount,
            minReturn,
            _auxData
        );

        bought = _getBalance(outputToken);
        require(bought >= minReturn, "LimitOrder::Tokens bought are not enough");

        _transferAmount(outputToken, _owner, bought);

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

        return handler.canHandle(
            _inputToken,
            outputToken,
            _inputAmount,
            minReturn,
            _auxData
        );
    }

    /**
     * @notice Get this contract's balance of token or Ether
     * @param _token - Address of the input token
     * @return uint256 - this contract's balance of _token
     */
    function _getBalance(IERC20 _token) internal view returns (uint256) {
        if (address(_token) == ETH_ADDRESS) {
            return address(this).balance;
        } else {
            return _token.balanceOf(address(this));
        }
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
    ) internal {
        if (address(_token) == ETH_ADDRESS) {
            (bool success,) = _to.call{value: _amount}("");
            require(success, "LimitOrder::Error sending ETH to the handler contract");
        } else {
            _token.transfer(_to, _amount);
        }
    }
}