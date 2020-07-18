// SPDX-License-Identifier: GPL-2.0

pragma solidity ^0.6.8;

import "../../libs/SafeMath.sol";
import "../../commons/Order.sol";
import "../../interfaces/IERC20.sol";
import "../../interfaces/IRelayer.sol";
import "../../interfaces/uniswapV1/UniswapExchange.sol";
import "../../interfaces/uniswapV1/UniswapFactory.sol";
import "../../interfaces/uniswapV2/IUniswapV2Router.sol";


contract UniswapRelayer is IRelayer, Order {

    using SafeMath for uint256;

    uint256 private constant never = uint(-1);

    UniswapFactory public uniswapFactory;

    IUniswapV2Router public uniswapV2Router;

    address public WETH_TOKEN;

    constructor(UniswapFactory _uniswapFactory, IUniswapV2Router _uniswapV2Router) public {
        uniswapFactory = _uniswapFactory;

        uniswapV2Router = _uniswapV2Router;

        WETH_TOKEN = uniswapV2Router.WETH();
    }

    receive() external override payable { }

    function execute(
        IERC20 _inputToken,
        uint256 _inputAmount,
        address payable /*_owner */,
        bytes calldata _data,
        bytes calldata _auxData
    ) external payable override returns (uint256 bought) {
         (
            IERC20 outputToken,,
            uint256 fee
        ) = abi.decode(
            _data,
            (
                IERC20,
                uint256,
                uint256
            )
        );

        (,address payable relayer, uint8 version) = abi.decode(_auxData, (address, address, uint8));

         if (address(_inputToken) == ETH_ADDRESS) {
            // Keep some eth for paying the fee
            uint256 sell = _inputAmount.sub(fee);
            bought = _ethToToken(version, outputToken, sell, msg.sender);

            (bool success,) = relayer.call{value: fee}("");
            require(success, "Error sending fees to the relayer");
        } else if (address(outputToken) == ETH_ADDRESS) {
            // Convert
            bought = _tokenToEth(version, _inputToken, _inputAmount, address(this));
            bought = bought.sub(fee);

            // Send fee and amount bought
            // @TODO: Review if it is the best way or 1 require is better cosuming less gas
            (bool successRelayer,) =  relayer.call{value: fee}("");
            require(successRelayer, "Error sending fees to the relayer");

            (bool successSender,) = msg.sender.call{value: bought}("");
            require(successSender, "Error sending ETH to the order owner");
        } else {
            // Convert from fromToken to ETH
            uint256 boughtEth = _tokenToEth(version, _inputToken, _inputAmount, address(this));
            (bool success,) = relayer.call{value: fee}("");
            require(success, "Error sending fees to the relayer");

            // Convert from ETH to toToken
            bought = _ethToToken(version, outputToken, boughtEth.sub(fee), msg.sender);
        }
    }

    function canExecute(
        IERC20 _inputToken,
        uint256 _inputAmount,
        bytes calldata _data,
        bytes calldata _auxData
    ) external override view returns (bool) {
        (IERC20 outputToken, uint256 minReturn, uint256 fee) = abi.decode(
            _data,
            (
                IERC20,
                uint256,
                uint256
            )
        );

        (,,uint8 version) = abi.decode(_auxData, (address, address, uint8));

        uint256 bought;

        if (address(_inputToken) == ETH_ADDRESS) {
            if (_inputAmount <= fee) {
                return false;
            }

            uint256 sell = _inputAmount.sub(fee);
            bought = _outEthToToken(version, outputToken, sell);
        } else if (address(outputToken) == ETH_ADDRESS) {
            bought = _outTokenToEth(version, _inputToken, _inputAmount);

            if (bought <= fee) {
                return false;
            }

            bought = bought.sub(fee);
        } else {
            uint256 boughtEth =  _outTokenToEth(version, _inputToken, _inputAmount);
            if (boughtEth <= fee) {
                return false;
            }

            bought = _outEthToToken(version, outputToken, boughtEth.sub(fee));
        }

        return bought >= minReturn;
    }

     function getBestPath(
        IERC20 _inputToken,
        uint256 _inputAmount,
        bytes calldata _data
    ) external view returns (uint8) {
        (IERC20 outputToken, uint256 minReturn, uint256 fee) = abi.decode(
            _data,
            (
                IERC20,
                uint256,
                uint256
            )
        );

        uint256 boughtV1;
        uint256 boughtV2;

        if (address(_inputToken) == ETH_ADDRESS) {
            uint256 sell = _inputAmount.sub(fee);
            boughtV1 = _outEthToTokenV1(outputToken, sell);
            boughtV2 = _outEthToTokenV2(outputToken, sell);
        } else if (address(outputToken) == ETH_ADDRESS) {
            boughtV1 = _outTokenToEthV1(_inputToken, _inputAmount).sub(fee);
            boughtV2 = _outTokenToEthV2(_inputToken, _inputAmount).sub(fee);
        } else {
            uint256 boughtEthV1 = _outTokenToEthV1(_inputToken, _inputAmount);
            boughtV1 = _outEthToTokenV1(outputToken, boughtEthV1.sub(fee));

            uint256 boughtEthV2 = _outTokenToEthV2(_inputToken, _inputAmount);
            boughtV2 = _outEthToTokenV2(outputToken, boughtEthV2.sub(fee));
        }

        if (boughtV1 >= minReturn && boughtV1 >= boughtV2) {
            return 1;
        } else if (boughtV2 >= minReturn && boughtV2 > boughtV1) {
            return 2;
        } else {
            return 0;
        }
    }

    function _ethToToken(
        uint8 _version,
        IERC20 _token,
        uint256 _amount,
        address _dest
    ) private returns (uint256) {
        if (_version == 1) {
            return _ethToTokenV1(uniswapFactory, _token, _amount, _dest);
        } else {
            return _ethToTokenV2(uniswapV2Router, _token, _amount, _dest);
        }
    }

    function _ethToTokenV1(
        UniswapFactory _uniswapFactory,
        IERC20 _token,
        uint256 _amount,
        address _dest
    ) private returns (uint256) {
        UniswapExchange uniswap = _uniswapFactory.getExchange(address(_token));

        return uniswap.ethToTokenTransferInput{value: _amount}(1, never, _dest);
    }

    function _ethToTokenV2(
        IUniswapV2Router _uniswapV2Router,
        IERC20 _token,
        uint256 _amount,
        address _dest
    ) private returns (uint256) {
        address[] memory path = new address[](2);

        path[0] = WETH_TOKEN;
        path[1] = address(_token);

        return _uniswapV2Router.swapExactETHForTokens{
            value: _amount
        }(
            1,
            path,
            _dest,
            block.timestamp
        )[1];
    }

    function _tokenToEth(
        uint _version,
        IERC20 _token,
        uint256 _amount,
        address _dest
    ) private returns (uint256) {
        if (_version == 1) {
            return _tokenToEthV1(uniswapFactory, _token, _amount);
        } else {
            return _tokenToEthV2(uniswapV2Router, _token, _amount, _dest);
        }
    }

    function _tokenToEthV1(
        UniswapFactory _uniswapFactory,
        IERC20 _token,
        uint256 _amount
    ) private returns (uint256) {
        UniswapExchange uniswap = _uniswapFactory.getExchange(address(_token));
        require(address(uniswap) != address(0), "The exchange should exist");

        // Check if previous allowance is enough and approve Uniswap if not
        uint256 prevAllowance = _token.allowance(address(this), address(uniswap));
        if (prevAllowance < _amount) {
            if (prevAllowance != 0) {
                _token.approve(address(uniswap), 0);
            }

            _token.approve(address(uniswap), uint(-1));
        }

        // Execute the trade
        return uniswap.tokenToEthSwapInput(_amount, 1, never);
    }

    function _tokenToEthV2(
        IUniswapV2Router _uniswapV2Router,
        IERC20 _token,
        uint256 _amount,
        address _dest
    ) private returns (uint256) {
        address[] memory path = new address[](2);

        path[0] = address(_token);
        path[1] = WETH_TOKEN;

        // Check if previous allowance is enough and approve Uniswap if not
        uint256 prevAllowance = _token.allowance(address(this), address(_uniswapV2Router));
        if (prevAllowance < _amount) {
            if (prevAllowance != 0) {
                _token.approve(address(_uniswapV2Router), 0);
            }

            _token.approve(address(_uniswapV2Router), uint(-1));
        }

        // Execute the trade
        return _uniswapV2Router.swapExactTokensForETH(_amount, 1, path, _dest, block.timestamp)[1];
    }

    function _outEthToToken(uint8 _version, IERC20 _token, uint256 _amount) private view returns (uint256) {
         if (_version == 1) {
            return _outEthToTokenV1(_token, _amount);
        } else {
            return _outEthToTokenV2(_token, _amount);
        }
    }

    function _outEthToTokenV1(IERC20 _token, uint256 _amount) private view returns (uint256) {
        return uniswapFactory.getExchange(address(_token)).getEthToTokenInputPrice(_amount);
    }

     function _outEthToTokenV2(IERC20 _token, uint256 _amount) private view returns (uint256) {
        address[] memory path = new address[](2);

        path[0] = WETH_TOKEN;
        path[1] = address(_token);

        return uniswapV2Router.getAmountsOut(_amount, path)[1];
    }

    function _outTokenToEth(uint8 _version, IERC20 _token, uint256 _amount) private view returns (uint256) {
         if (_version == 1) {
            return _outEthToTokenV1(_token, _amount);
        } else {
            return _outEthToTokenV2(_token, _amount);
        }
    }

    function _outTokenToEthV1(IERC20 _token, uint256 _amount) private view returns (uint256) {
        return uniswapFactory.getExchange(address(_token)).getTokenToEthInputPrice(_amount);
    }

    function _outTokenToEthV2(IERC20 _token, uint256 _amount) private view returns (uint256) {
        address[] memory path = new address[](2);

        path[0] = address(_token);
        path[1] = WETH_TOKEN;

        return uniswapV2Router.getAmountsOut(_amount, path)[1];
    }

}