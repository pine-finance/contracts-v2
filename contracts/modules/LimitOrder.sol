// SPDX-License-Identifier: GPL-2.0

pragma solidity ^0.6.8;

import "../interfaces/IModule.sol";
import "../interfaces/IRelayer.sol";
import "../commons/Order.sol";
import "../libs/SafeMath.sol";


contract LimitOrder is IModule, Order {
    using SafeMath for uint256;

    receive() external override payable { }

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

        uint256 prevBalance = _getBalance(outputToken);

        (IRelayer relayerExecutor) = abi.decode(_auxData, (IRelayer));

        _transferAmount(_inputToken, address(relayerExecutor), _inputAmount);

        relayerExecutor.execute(
            _inputToken,
            _inputAmount,
            _owner,
            _data,
            _auxData
        );

        uint256 afterBalance = _getBalance(outputToken);
        bought = afterBalance.sub(prevBalance);

        require(bought >= minReturn, "Tokens bought are not enough");

        _transferAmount(outputToken, _owner, bought);

        return bought;
    }

    function canExecute(
        IERC20 _inputToken,
        uint256 _inputAmount,
        bytes calldata _data,
        bytes calldata _auxData
    ) external override view returns (bool) {
        (IRelayer relayerExecutor) = abi.decode(_auxData, (IRelayer));

        return relayerExecutor.canExecute(
            _inputToken,
            _inputAmount,
            _data,
            _auxData
        );
    }

    function _getBalance(IERC20 _token) internal view returns (uint256) {
        if (address(_token) == ETH_ADDRESS) {
            return address(this).balance;
        } else {
            return _token.balanceOf(address(this));
        }
    }

    function _transferAmount(
        IERC20 _token,
        address payable _to,
        uint256 _amount
    ) internal {
        if (address(_token) == ETH_ADDRESS) {
            (bool success,) = _to.call{value: _amount}("");
            require(success, "Error sending ETH to the relayer contract");
        } else {
            _token.transfer(_to, _amount);
        }
    }
}