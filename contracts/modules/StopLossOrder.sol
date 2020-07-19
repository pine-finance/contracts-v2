// SPDX-License-Identifier: GPL-2.0

pragma solidity ^0.6.8;
pragma experimental ABIEncoderV2;

import "../interfaces/IModule.sol";
import "../interfaces/IHandler.sol";
import "../interfaces/uniswapV1/UniswapExchange.sol";
import "../interfaces/uniswapV1/UniswapFactory.sol";
import "../libs/SafeMath.sol";
import "../commons/FixedWindowOracle.sol";
import "../utils/UniswapExUtils.sol";


contract StopLossOrder is IModule {
    using SafeMath for uint256;

    uint256 private constant BASE = 1000;

    address public immutable UNISWAPEX;

    UniswapFactory public immutable UNISWAP_FACTORY;
    FixedWindowOracle public immutable ORACLE;

    constructor(
        UniswapFactory _uniswapFactory,
        FixedWindowOracle _oracle,
        address _uniswapex
    ) public {
        UNISWAP_FACTORY = _uniswapFactory;
        ORACLE = _oracle;
        UNISWAPEX = _uniswapex;
    }

    struct StopLossData {
        IERC20 outputToken;
        uint256 maxReceive;
        uint256 minReceivePart;
        uint256 maxDelta;
    }

    modifier onlyUniswapEx() {
        require(msg.sender == UNISWAPEX, "StopLossOrder#onlyUniswapEx: NOT_UNISWAPEX");
        _;
    }

    receive() external override payable onlyUniswapEx { }

    /**
        @notice Tries to send an amount of tokens or ETH, if the transfer fails
            it tries to send the current balance of the contract
    */
    function _tryOrSendAll(
        IERC20 _token,
        address _to,
        uint256 _estimatedAmount
    ) internal returns (bool, uint256) {
        if (UniswapExUtils.transfer(_token, _to, _estimatedAmount)) {
            return (true, _estimatedAmount);
        }

        uint256 fullBalance = UniswapExUtils.balanceOf(_token, address(this));
        return (UniswapExUtils.transfer(_token, _to, fullBalance), fullBalance);
    }

    function execute(
        IERC20 _inputToken,
        uint256 _inputAmount,
        address payable _owner,
        bytes calldata _data,
        bytes calldata _auxData
    ) external override onlyUniswapEx returns (uint256 bought) {
        StopLossData memory order = abi.decode(_data, (StopLossData));
        uint256 minReceive;

        { // Avoid stack too deep
            (uint256 outputAmount, uint256 delta) = ORACLE.consult(
                address(_inputToken),
                address(order.outputToken),
                _inputAmount
            );

            // Check stop loss order limits
            require(delta <= order.maxDelta, "StopLossOrder#execute: DELTA_TOO_HIGH");
            require(outputAmount < order.maxReceive, "StopLossOrder#execute: PRICE_TOO_HIGH");

            minReceive = outputAmount.mul(order.minReceivePart) / BASE;
        }

        // Decode aux-data
        (address handler, bytes memory auxData) = abi.decode(_auxData, (address, bytes));

        // Send all inputTokens to handler
        // Don't check if sending tokens failed, handler should check that
        (, uint256 sent) = _tryOrSendAll(_inputToken, handler, _inputAmount);

        // Call handler if required
        if (auxData.length > 0) {
            bought = IHandler(handler).handle(
                _inputToken,
                order.outputToken,
                sent,
                minReceive,
                auxData
            );
        } else {
            bought = UniswapExUtils.balanceOf(order.outputToken, address(this));
        }

        // Require enough bough tokens
        // and send tokens to the owner
        bool success;
        (success, bought) = _tryOrSendAll(order.outputToken, _owner, bought);
        require(success, "StopLossOrder#execute: ERROR_SENDING_BOUGHT_TOKENS");
        require(bought >= minReceive, "StopLossOrder#execute: BOUGHT_NOT_ENOUGH");
    }

    function canExecute(
        IERC20 _inputToken,
        uint256 _inputAmount,
        bytes calldata _data,
        bytes calldata _auxData
    ) external override view returns (bool) {
        StopLossData memory order = abi.decode(_data, (StopLossData));
        uint256 minReceive;

        { // Avoid stack too deep
            (uint256 outputAmount, uint256 delta) = ORACLE.read(
                address(_inputToken),
                address(order.outputToken),
                _inputAmount
            );

            // Check stop loss order limits
            if (delta > order.maxDelta) return false;
            if (outputAmount >= order.maxReceive) return false;

            minReceive = outputAmount.mul(order.minReceivePart) / BASE;
        }

        // Decode aux-data
        (address handler, bytes memory auxData) = abi.decode(_auxData, (address, bytes));
        if (handler != address(0)) {
            return IHandler(handler).canHandle(
                _inputToken,
                order.outputToken,
                _inputAmount,
                minReceive,
                auxData
            );
        }

        return true;
    }
}
