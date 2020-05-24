// SPDX-License-Identifier: GPL-2.0

pragma solidity ^0.6.8;


import "./libs/SafeMath.sol";
import "./libs/ECDSA.sol";
import "./libs/Fabric.sol";
import "./interfaces/IModule.sol";
import "./interfaces/IERC20.sol";


contract UniswapEX {
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
        address _fromToken,
        address _toToken,
        uint256 _minReturn,
        uint256 _fee,
        address _owner,
        address _witness,
        address _relayer,
        uint256 _amount
    );

    event OrderCancelled(
        bytes32 indexed _key,
        address _fromToken,
        address _toToken,
        uint256 _minReturn,
        uint256 _fee,
        address _owner,
        address _witness,
        uint256 _amount
    );

    address public constant ETH_ADDRESS = address(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);
    uint256 private constant never = uint(-1);

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
        //@TODO: Nacho: Remove fromToken and replace by a PUSH 0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee directly
        (
            address module,
            address fromToken,
            address toToken,
            uint256 minReturn,
            uint256 fee,
            address payable owner,
            ,
            address witness
        ) = decodeOrder(_data);

        require(fromToken == ETH_ADDRESS, "order is not from ETH");

        bytes32 key = _keyOf(
            IModule(module),
            IERC20(fromToken),
            IERC20(toToken),
            minReturn,
            fee,
            owner,
            witness
        );

        ethDeposits[key] = ethDeposits[key].add(msg.value);
        emit DepositETH(key, msg.sender, msg.value, _data);
    }

    function cancelOrder(
        IModule _module,
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _minReturn,
        uint256 _fee,
        address payable _owner,
        address _witness
    ) external {
        require(msg.sender == _owner, "Only the owner of the order can cancel it");
        bytes32 key = _keyOf(
            _module,
            _fromToken,
            _toToken,
            _minReturn,
            _fee,
            _owner,
            _witness
        );

        uint256 amount;
        if (address(_fromToken) == ETH_ADDRESS) {
            amount = ethDeposits[key];
            ethDeposits[key] = 0;
            msg.sender.transfer(amount);
        } else {
            amount = key.executeVault(_fromToken, msg.sender);
        }

        emit OrderCancelled(
            key,
            address(_fromToken),
            address(_toToken),
            _minReturn,
            _fee,
            _owner,
            _witness,
            amount
        );
    }

    function executeOrder(
        IModule _module,
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _minReturn,
        uint256 _fee,
        address payable _owner,
        bytes calldata _witnesses,
        bytes calldata _data
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
            _fromToken,
            _toToken,
            _minReturn,
            _fee,
            _owner,
            witness
        );

        // Pull amount
        uint256 amount = _pullOrder(_fromToken, key);
        require(amount > 0, "The order does not exists");

        _module.execute(abi.encode(
            _fromToken,
            _toToken,
            _minReturn,
            _fee,
            _owner,
            amount,
            _data
        ));

        emit OrderExecuted(
            key,
            address(_fromToken),
            address(_toToken),
            _minReturn,
            _fee,
            _owner,
            witness,
            msg.sender,
            amount
        );
    }

    function encodeTokenOrder(
        IModule _module,
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _amount,
        uint256 _minReturn,
        uint256 _fee,
        address payable _owner,
        bytes32 _secret,
        address _witness
    ) external view returns (bytes memory) {
        return abi.encodeWithSelector(
            _fromToken.transfer.selector,
            vaultOfOrder(
                _module,
                _fromToken,
                _toToken,
                _minReturn,
                _fee,
                _owner,
                _witness
            ),
            _amount,
            abi.encode(
                _fromToken,
                _toToken,
                _minReturn,
                _fee,
                _owner,
                _secret,
                _witness
            )
        );
    }

    function encodeEthOrder(
        address _module,
        address _fromToken,
        address _toToken,
        uint256 _minReturn,
        uint256 _fee,
        address payable _owner,
        bytes32 _secret,
        address _witness
    ) external pure returns (bytes memory) {
        return abi.encode(
            _module,
            _fromToken,
            _toToken,
            _minReturn,
            _fee,
            _owner,
            _secret,
            _witness
        );
    }

    function decodeOrder(
        bytes memory _data
    ) public pure returns (
        address module,
        address fromToken,
        address toToken,
        uint256 minReturn,
        uint256 fee,
        address payable owner,
        bytes32 secret,
        address witness
    ) {
        (
            module,
            fromToken,
            toToken,
            minReturn,
            fee,
            owner,
            secret,
            witness
        ) = abi.decode(
            _data,
            (
                address,
                address,
                address,
                uint256,
                uint256,
                address,
                bytes32,
                address
            )
        );
    }

    function existOrder(
        IModule _module,
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _minReturn,
        uint256 _fee,
        address payable _owner,
        address _witness
    ) external view returns (bool) {
        bytes32 key = _keyOf(
            _module,
            _fromToken,
            _toToken,
            _minReturn,
            _fee,
            _owner,
            _witness
        );

        if (address(_fromToken) == ETH_ADDRESS) {
            return ethDeposits[key] != 0;
        } else {
            return _fromToken.balanceOf(key.getVault()) != 0;
        }
    }

    function canExecuteOrder(
        IModule _module,
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _minReturn,
        uint256 _fee,
        address payable _owner,
        address _witness,
        bytes calldata _data
    ) external view returns (bool) {
        bytes32 key = _keyOf(
            _module,
            _fromToken,
            _toToken,
            _minReturn,
            _fee,
            _owner,
            _witness
        );

        // Pull amount
        uint256 amount;
        if (address(_fromToken) == ETH_ADDRESS) {
            amount = ethDeposits[key];
        } else {
            amount = _fromToken.balanceOf(key.getVault());
        }

        return _module.canExecute(abi.encode(
            _fromToken,
            _toToken,
            _minReturn,
            _fee,
            _owner,
            amount,
            _data
        ));
    }

    function vaultOfOrder(
        IModule _module,
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _minReturn,
        uint256 _fee,
        address payable _owner,
        address _witness
    ) public view returns (address) {
        return _keyOf(
            _module,
            _fromToken,
            _toToken,
            _minReturn,
            _fee,
            _owner,
            _witness
        ).getVault();
    }

    function _pullOrder(
        IERC20 _fromToken,
        bytes32 _key
    ) private returns (uint256 amount) {
        if (address(_fromToken) == ETH_ADDRESS) {
            amount = ethDeposits[_key];
            ethDeposits[_key] = 0;
        } else {
            amount = _key.executeVault(_fromToken, address(this));
        }
    }

    function _keyOf(
        IModule _module,
        IERC20 _fromToken,
        IERC20 _toToken,
        uint256 _minReturn,
        uint256 _fee,
        address payable _owner,
        address _witness
    ) private pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _module,
                _fromToken,
                _toToken,
                _minReturn,
                _fee,
                _owner,
                _witness
            )
        );
    }
}