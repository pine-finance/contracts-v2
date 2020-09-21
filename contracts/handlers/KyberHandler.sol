// SPDX-License-Identifier: GPL-2.0

pragma solidity ^0.6.8;

import "../libs/SafeMath.sol";
import "../libs/PineUtils.sol";
import "../commons/Order.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IHandler.sol";


interface IKyberNetworkProxy {
    function trade(
        IERC20 src,
        uint256 srcAmount,
        IERC20 dest,
        address destAddress,
        uint256 maxDestAmount,
        uint256 minConversionRate,
        address walletId
    )
    external payable returns (uint256);
}


/// @notice Kyber Handler used to execute an order
contract KyberHandler is IHandler, Order {

    using SafeMath for uint256;

    uint256 private constant never = uint(-1);

    IKyberNetworkProxy private immutable kyberProxy;

    /**
     * @notice Creates the handler
     * @param _kyberProxy - KyberProxy contract
     */
    constructor(address _kyberProxy) public {
        kyberProxy = IKyberNetworkProxy(_kyberProxy);
    }

    /// @notice receive ETH
    receive() external override payable {
        require(msg.sender != tx.origin, "KyberHandler#receive: NO_SEND_ETH_PLEASE");
    }

    /**
     * @notice Handle an order execution
     * @param _inputToken - Address of the input token
     * @param _outputToken - Address of the output token
     * @param _data - Bytes of arbitrary data
     * @return bought - Amount of output token bought
     */
    function handle(
        IERC20 _inputToken,
        IERC20 _outputToken,
        uint256,
        uint256,
        bytes calldata _data
    ) external payable override returns (uint256 bought) {
        // Load real initial balance, don't trust provided value
        uint256 inputAmount = PineUtils.balanceOf(_inputToken, address(this));

        (,address payable relayer, uint256 fee) = abi.decode(_data, (address, address, uint256));

        if (address(_inputToken) == ETH_ADDRESS) {
            // Keep some eth for paying the fee
            uint256 sell = inputAmount.sub(fee);
            bought = _swap(_inputToken, _outputToken, sell, msg.sender);
        } else if (address(_outputToken) == ETH_ADDRESS) {
            // Convert
            bought = _swap(_inputToken, _outputToken, inputAmount, address(this));
            bought = bought.sub(fee);

            // Send amount bought
            (bool successSender,) = msg.sender.call{value: bought}("");
            require(successSender, "KyberHandler#handle: TRANSFER_ETH_TO_CALLER_FAILED");
        } else {
            // Convert from fromToken to ETH
            uint256 boughtEth = _swap(_inputToken, IERC20(ETH_ADDRESS), inputAmount, address(this));

            // Convert from ETH to toToken
            bought = _swap(IERC20(ETH_ADDRESS), _outputToken, boughtEth.sub(fee), msg.sender);
        }

        // Send fee to relayer
        (bool successRelayer,) = relayer.call{value: fee}("");
        require(successRelayer, "KyberHandler#handle: TRANSFER_ETH_TO_RELAYER_FAILED");
    }

    /**
     * @notice Trade token to ETH
     * @param _inputToken - Address of the input token
     * @param _outputToken - Address of the output token
     * @param _amount - uint256 of the input token amount
     * @param _recipient - address of the recepient
     * @return bought - Amount of ETH bought
     */
    function _swap(
        IERC20 _inputToken,
        IERC20 _outputToken,
        uint256 _amount,
        address _recipient
    ) private returns (uint256) {
        uint256 value = 0;
        if (_inputToken != IERC20(ETH_ADDRESS)) {
        // Check if previous allowance is enough and approve kyberProxy if not
            uint256 prevAllowance = _inputToken.allowance(address(this), address(kyberProxy));
            if (prevAllowance < _amount) {
                if (prevAllowance != 0) {
                    _inputToken.approve(address(kyberProxy), 0);
                }

                _inputToken.approve(address(kyberProxy), uint(-1));
            }
        } else {
            value = _amount;
        }

        return kyberProxy.trade{value: value}(
            _inputToken,  // srcToken
            _amount, // srcAmount
            _outputToken, // dstToken
            _recipient, // dstAddress
            never, // maxDstAmount
            0, // minConversion Rate
            address(0) // walletId for fees sharing
        );
    }

    /**
     * @notice Check whether can handle an order execution
     * @return bool - Whether the execution can be handled or not
     */
    function canHandle(
        IERC20,
        IERC20,
        uint256,
        uint256,
        bytes calldata
    ) external override view returns (bool) {
       return true;
    }
}
