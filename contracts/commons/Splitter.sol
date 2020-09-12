// SPDX-License-Identifier: GPL-2.0

pragma solidity ^0.6.8;

import "./Ownable.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/IERC20.sol";
import "../libs/PineUtils.sol";
import "../libs/SafeERC20.sol";


contract Splitter is Ownable {
    IWETH private immutable iweth;

    address public a;
    address public b;

    event SetA(address _a);
    event SetB(address _b);

    constructor(
        IWETH _iweth,
        address payable _a,
        address payable _b,
        address _owner
    ) public Ownable(_owner) {
        iweth = _iweth;
        a = _a;
        b = _b;
        emit SetA(_a);
        emit SetB(_b);
    }

    function transferA(address _to) external {
        require(_to != address(0), "wrong value");
        require(msg.sender == a || msg.sender == _owner, "not authorized");
        emit SetA(_to);
        a = _to;
    }

    function transferB(address _to) external {
        require(_to != address(0), "wrong value");
        require(msg.sender == b || msg.sender == _owner, "not authorized");
        emit SetB(_to);
        b = _to;
    }

    function withdraw(address[] calldata _tokens, uint256[] calldata _amounts) external {
        address addra = a;
        address addrb = b;

        uint256 total = _tokens.length;
        require(_amounts.length == total, "invalid arrays");

        for (uint256 i = 0; i < total; i++) {
            // Load token and amount
            address token = _tokens[i];
            uint256 amount = _amounts[i];

            // Wrap as WETH if ETH 
            if (token == PineUtils.ETH_ADDRESS) {
                iweth.deposit{ value: amount }();
                token = address(iweth);
            }

            // Split in two and send to the two addresses
            uint256 send = amount / 2;
            require(SafeERC20.transfer(IERC20(token), addra, send), "error sending tokens to a");
            require(SafeERC20.transfer(IERC20(token), addrb, send), "error sending tokens to b");
        }
    }

    function execute(address _to, uint256 _val, bytes calldata _data) external onlyOwner {
        _to.call{ value: _val }(_data);
    }

    receive() payable external { }
}
