// SPDX-License-Identifier: GPL-2.0

pragma solidity ^0.6.8;
pragma experimental ABIEncoderV2;

import "../interfaces/IModule.sol";
import "../interfaces/IStopLossHandler.sol";
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
    function _sendAll(
        IERC20 _token,
        address _to,
        uint256 _estimatedAmount
    ) internal returns (bool) {
        return (
            UniswapExUtils.transfer(_token, _to, _estimatedAmount) ||
            UniswapExUtils.transfer(_token, _to, UniswapExUtils.balanceOf(_token, address(this)))
        );
    }

    function execute(
        IERC20 _inputToken,
        uint256 _inputAmount,
        address payable _owner,
        bytes calldata _data,
        bytes calldata _auxData
    ) external override onlyUniswapEx returns (uint256 bought) {
        StopLossData memory order = abi.decode(_data, (StopLossData));

        uint256 outputAmount;

        { // Avoid stack too deep
            uint256 delta;
            (outputAmount, delta) = ORACLE.consult(
                address(_inputToken),
                address(order.outputToken),
                _inputAmount
            );

            // Check stop loss order limits
            require(delta <= order.maxDelta, "StopLossOrder#execute: DELTA_TOO_HIGH");
            require(outputAmount < order.maxReceive, "StopLossOrder#execute: PRICE_TOO_HIGH");
        }

        // Compute minReceive as a factor of oracle reading
        uint256 minReceive = outputAmount.mul(order.minReceivePart) / BASE;

        // Decode aux-data
        (address handler, bytes memory auxData) = abi.decode(_auxData, (address, bytes));

        // Send all inputTokens to handler
        _sendAll(_inputToken, handler, _inputAmount);

        // Call handler
        // TODO: Check reentrancy
        IStopLossHandler(handler).handle(
            _inputToken,
            order.outputToken,
            _inputAmount,
            minReceive,
            auxData
        );

        // Require enough bough tokens
        bought = UniswapExUtils.balanceOf(order.outputToken, address(this));
        require(bought >= minReceive, "StopLossOrder#execute: BOUGHT_NOT_ENOUGH");

        // Send tokens to owner
        UniswapExUtils.transfer(order.outputToken, _owner, bought);
    }

    function canExecute(
        IERC20 _inputToken,
        uint256 _inputAmount,
        bytes calldata _data,
        bytes calldata _auxData
    ) external override view returns (bool) {

    }
}
