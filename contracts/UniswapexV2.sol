// SPDX-License-Identifier: GPL-2.0

pragma solidity ^0.6.8;


import "./libs/SafeMath.sol";
import "./libs/ECDSA.sol";
import "./libs/Fabric.sol";
import "./interfaces/IModule.sol";
import "./interfaces/IERC20.sol";
import "./commons/Order.sol";


contract UniswapexV2 is Order{
    using SafeMath for uint256;
    using Fabric for bytes32;

    event DepositETH(
        bytes32 indexed _key,
        address indexed _caller,
        uint256 _amount,
        bytes _data
    );

    event OrderExecuted(
        bytes32 indexed _key,
        address _inputToken,
        address _owner,
        address _witness,
        bytes _data,
        bytes _auxData,
        uint256 _amount,
        uint256 _bought
    );

    event OrderCancelled(
        bytes32 indexed _key,
        address _inputToken,
        address _owner,
        address _witness,
        bytes _data,
        uint256 _amount
    );

    mapping(bytes32 => uint256) public ethDeposits;

    receive() external payable {
        require(
            msg.sender != tx.origin,
            "Prevent sending ETH directly to the contract"
        );
    }

    function depositEth(
        bytes calldata _data
    ) external payable {
        require(msg.value > 0, "No value provided");
        (
            address module,
            address inputToken,
            address payable owner,
            address witness,
            bytes memory data,
        ) = decodeOrder(_data);

        require(inputToken == ETH_ADDRESS, "order is not from ETH");

        bytes32 key = _keyOf(
            IModule(uint160(module)),
            IERC20(inputToken),
            owner,
            witness,
            data
        );

        ethDeposits[key] = ethDeposits[key].add(msg.value);
        emit DepositETH(key, msg.sender, msg.value, _data);
    }

    function cancelOrder(
        IModule _module,
        IERC20 _inputToken,
        address payable _owner,
        address _witness,
        bytes calldata _data
    ) external {
        require(msg.sender == _owner, "Only the owner of the order can cancel it");
        bytes32 key = _keyOf(
            _module,
            _inputToken,
            _owner,
            _witness,
            _data
        );

        uint256 amount;
        if (address(_inputToken) == ETH_ADDRESS) {
            amount = ethDeposits[key];
            ethDeposits[key] = 0;
            msg.sender.transfer(amount);
        } else {
            amount = key.executeVault(_inputToken, msg.sender);
        }

        emit OrderCancelled(
            key,
            address(_inputToken),
            _owner,
            _witness,
            _data,
            amount
        );
    }

    function encodeTokenOrder(
        IModule _module,
        IERC20 _inputToken,
        address payable _owner,
        address _witness,
        bytes calldata _data,
        bytes32 _secret,
        uint256 _amount
    ) external view returns (bytes memory) {
        return abi.encodeWithSelector(
            _inputToken.transfer.selector,
            vaultOfOrder(
                _module,
                _inputToken,
                _owner,
                _witness,
                _data
            ),
            _amount,
            abi.encode(
                _inputToken,
                _owner,
                _witness,
                _data,
                _secret
            )
        );
    }

    function encodeEthOrder(
        address _module,
        address _inputToken,
        address payable _owner,
        address _witness,
        bytes calldata _data,
        bytes32 _secret
    ) external pure returns (bytes memory) {
        return abi.encode(
            _module,
            _inputToken,
            _owner,
            _witness,
            _data,
            _secret
        );
    }

    function decodeOrder(
        bytes memory _data
    ) public pure returns (
        address module,
        address inputToken,
        address payable owner,
        address witness,
        bytes memory data,
        bytes32 secret
    ) {
        (
            module,
            inputToken,
            owner,
            witness,
            data,
            secret
        ) = abi.decode(
            _data,
            (
                address,
                address,
                address,
                address,
                bytes,
                bytes32
            )
        );
    }

    function existOrder(
        IModule _module,
        IERC20 _inputToken,
        address payable _owner,
        address _witness,
        bytes calldata _data
    ) external view returns (bool) {
        bytes32 key = _keyOf(
            _module,
            _inputToken,
            _owner,
            _witness,
           _data
        );

        if (address(_inputToken) == ETH_ADDRESS) {
            return ethDeposits[key] != 0;
        } else {
            return _inputToken.balanceOf(key.getVault()) != 0;
        }
    }

    function vaultOfOrder(
        IModule _module,
        IERC20 _inputToken,
        address payable _owner,
        address _witness,
        bytes memory _data
    ) public view returns (address) {
        return _keyOf(
            _module,
            _inputToken,
            _owner,
            _witness,
            _data
        ).getVault();
    }


    function executeOrder(
        IModule _module,
        IERC20 _inputToken,
        address payable _owner,
        bytes calldata _data,
        bytes calldata _witnesses,
        bytes calldata _auxData
    ) external {
        // Calculate witness using signature
        // avoid front-run by requiring msg.sender to know
        // the secret
        address witness = ECDSA.recover(
            keccak256(abi.encodePacked(msg.sender)),
            _witnesses
        );

        bytes32 key = _keyOf(
            _module,
            _inputToken,
            _owner,
            witness,
            _data
        );

        // Pull amount
        uint256 amount = _pullOrder(_inputToken, key, address(_module));
        require(amount > 0, "The order does not exists");

        uint256 bought = _module.execute(
            _inputToken,
            amount,
            _owner,
            _data,
            _auxData
        );

        emit OrderExecuted(
            key,
            address(_inputToken),
            _owner,
            witness,
            _data,
            _auxData,
            amount,
            bought
        );
    }

    function canExecuteOrder(
        IModule _module,
        IERC20 _inputToken,
        address payable _owner,
        address _witness,
        bytes calldata _data,
        bytes calldata _auxData
    ) external view returns (bool) {
        bytes32 key = _keyOf(
            _module,
            _inputToken,
            _owner,
            _witness,
            _data
        );

        // Pull amount
        uint256 amount;
        if (address(_inputToken) == ETH_ADDRESS) {
            amount = ethDeposits[key];
        } else {
            amount = _inputToken.balanceOf(key.getVault());
        }

        return _module.canExecute(
            _inputToken,
            amount,
            _data,
            _auxData
        );
    }

    function _pullOrder(
        IERC20 _inputToken,
        bytes32 _key,
        address payable _to
    ) private returns (uint256 amount) {
        if (address(_inputToken) == ETH_ADDRESS) {
            amount = ethDeposits[_key];
            ethDeposits[_key] = 0;
            _to.transfer(amount);
        } else {
            amount = _key.executeVault(_inputToken, _to);
        }
    }

    function _keyOf(
        IModule _module,
        IERC20 _inputToken,
        address payable _owner,
        address _witness,
        bytes memory _data
    ) private pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _module,
                _inputToken,
                _owner,
                _witness,
                _data
            )
        );
    }
}