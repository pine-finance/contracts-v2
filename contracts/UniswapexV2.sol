// SPDX-License-Identifier: GPL-2.0

pragma solidity ^0.6.8;


import "./libs/SafeMath.sol";
import "./libs/ECDSA.sol";
import "./libs/Fabric.sol";
import "./interfaces/IModule.sol";
import "./interfaces/IERC20.sol";
import "./commons/Order.sol";


/// @notice Core contract used to create, cancel and execute orders.
contract UniswapexV2 is Order{
    using SafeMath for uint256;
    using Fabric for bytes32;

    // ETH orders
    mapping(bytes32 => uint256) public ethDeposits;

    // Events
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

    /**
     * @dev Prevent users to send Ether directly to this contract
     */
    receive() external payable {
        require(
            msg.sender != tx.origin,
            "UniswapexV2#receive: NO_SEND_ETH_PLEASE"
        );
    }

    /**
     * @notice Create an order from ETH to token
     * @param _data - Bytes of an ETH to token. See `encodeEthOrder` for more info
     */
    function depositEth(
        bytes calldata _data
    ) external payable {
        require(msg.value > 0, "UniswapexV2#depositEth: VALUE_IS_0");

        (
            address module,
            address inputToken,
            address payable owner,
            address witness,
            bytes memory data,
        ) = decodeOrder(_data);

        require(inputToken == ETH_ADDRESS, "UniswapexV2#depositEth: WRONG_INPUT_TOKEN");

        bytes32 key = keyOf(
            IModule(uint160(module)),
            IERC20(inputToken),
            owner,
            witness,
            data
        );

        ethDeposits[key] = ethDeposits[key].add(msg.value);
        emit DepositETH(key, msg.sender, msg.value, _data);
    }

    /**
     * @notice Cancel order
     * @dev The params should be the same used for the order creation
     * @param _module - Address of the module to use for the order execution
     * @param _inputToken - Address of the input token
     * @param _owner - Address of the order's owner
     * @param _witness - Address of the witness
     * @param _data - Bytes of the order's data
     */
    function cancelOrder(
        IModule _module,
        IERC20 _inputToken,
        address payable _owner,
        address _witness,
        bytes calldata _data
    ) external {
        require(msg.sender == _owner, "UniswapexV2#cancelOrder: INVALID_OWNER");
        bytes32 key = keyOf(
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
            (bool success,) = msg.sender.call{value: amount}("");
            require(success, "UniswapexV2#cancelOrder: ETHER_TRANSFER_FAILED");
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

    /**
     * @notice Get the calldata needed to create a token to token/ETH order
     * @dev Returns the input data that the user needs to use to create the order
     * The _secret is used to prevent a front-running at the order execution
     * The _amount is used as the param `_value` for the ERC20 `transfer` function
     * @param _module - Address of the module to use for the order execution
     * @param _inputToken - Address of the input token
     * @param _owner - Address of the order's owner
     * @param _witness - Address of the witness
     * @param _data - Bytes of the order's data
     * @param _secret - Private key of the _witness
     * @param _amount - uint256 of the order amount
     * @return bytes - input data to send the transaction
     */
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
                _module,
                _inputToken,
                _owner,
                _witness,
                _data,
                _secret
            )
        );
    }

    /**
     * @notice Get the calldata needed to create a ETH to token order
     * @dev Returns the input data that the user needs to use to create the order
     * The _secret is used to prevent a front-running at the order execution
     * @param _module - Address of the module to use for the order execution
     * @param _inputToken - Address of the input token
     * @param _owner - Address of the order's owner
     * @param _witness - Address of the witness
     * @param _data - Bytes of the order's data
     * @param _secret -  Private key of the _witness
     * @return bytes - input data to send the transaction
     */
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

    /**
     * @notice Get order's properties
     * @param _data - Bytes of the order
     * @return module - Address of the module to use for the order execution
     * @return inputToken - Address of the input token
     * @return owner - Address of the order's owner
     * @return witness - Address of the witness
     * @return data - Bytes of the order's data
     * @return secret -  Private key of the _witness
     */
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

    /**
     * @notice Get the vault's address of a token to token/ETH order
     * @param _module - Address of the module to use for the order execution
     * @param _inputToken - Address of the input token
     * @param _owner - Address of the order's owner
     * @param _witness - Address of the witness
     * @param _data - Bytes of the order's data
     * @return address - The address of the vault
     */
    function vaultOfOrder(
        IModule _module,
        IERC20 _inputToken,
        address payable _owner,
        address _witness,
        bytes memory _data
    ) public view returns (address) {
        return keyOf(
            _module,
            _inputToken,
            _owner,
            _witness,
            _data
        ).getVault();
    }

     /**
     * @notice Executes an order
     * @dev The sender should use the _secret to sign its own address
     * to prevent front-runnings
     * @param _module - Address of the module to use for the order execution
     * @param _inputToken - Address of the input token
     * @param _owner - Address of the order's owner
     * @param _data - Bytes of the order's data
     * @param _signature - Signature to calculate the witness
     * @param _auxData - Bytes of the auxiliar data used for the handlers to execute the order
     */
    function executeOrder(
        IModule _module,
        IERC20 _inputToken,
        address payable _owner,
        bytes calldata _data,
        bytes calldata _signature,
        bytes calldata _auxData
    ) external {
        // Calculate witness using signature
        address witness = ECDSA.recover(
            keccak256(abi.encodePacked(msg.sender)),
            _signature
        );

        bytes32 key = keyOf(
            _module,
            _inputToken,
            _owner,
            witness,
            _data
        );

        // Pull amount
        uint256 amount = _pullOrder(_inputToken, key, address(_module));
        require(amount > 0, "UniswapexV2#executeOrder: INVALID_ORDER");

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

     /**
     * @notice Check whether an order exists or not
     * @dev Check the balance of the order
     * @param _module - Address of the module to use for the order execution
     * @param _inputToken - Address of the input token
     * @param _owner - Address of the order's owner
     * @param _witness - Address of the witness
     * @param _data - Bytes of the order's data
     * @return bool - whether the order exists or not
     */
    function existOrder(
        IModule _module,
        IERC20 _inputToken,
        address payable _owner,
        address _witness,
        bytes calldata _data
    ) external view returns (bool) {
        bytes32 key = keyOf(
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

    /**
     * @notice Check whether an order can be executed or not
     * @param _module - Address of the module to use for the order execution
     * @param _inputToken - Address of the input token
     * @param _owner - Address of the order's owner
     * @param _witness - Address of the witness
     * @param _data - Bytes of the order's data
     * @param _auxData - Bytes of the auxiliar data used for the handlers to execute the order
     * @return bool - whether the order can be executed or not
     */
    function canExecuteOrder(
        IModule _module,
        IERC20 _inputToken,
        address payable _owner,
        address _witness,
        bytes calldata _data,
        bytes calldata _auxData
    ) external view returns (bool) {
        bytes32 key = keyOf(
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

    /**
     * @notice Transfer the order amount to a recipient.
     * @dev For an ETH order, the ETH will be transferred from this contract
     * For a token order, its vault will be executed transferring the amount of tokens to
     * the recipient
     * @param _inputToken - Address of the input token
     * @param _key - Order's key
     * @param _to - Address of the recipient
     * @return amount - amount transferred
     */
    function _pullOrder(
        IERC20 _inputToken,
        bytes32 _key,
        address payable _to
    ) private returns (uint256 amount) {
        if (address(_inputToken) == ETH_ADDRESS) {
            amount = ethDeposits[_key];
            ethDeposits[_key] = 0;
            (bool success,) = _to.call{value: amount}("");
            require(success, "UniswapexV2#_pullOrder: PULL_ETHER_FAILED");
        } else {
            amount = _key.executeVault(_inputToken, _to);
        }
    }

    /**
     * @notice Get the order's key
     * @param _module - Address of the module to use for the order execution
     * @param _inputToken - Address of the input token
     * @param _owner - Address of the order's owner
     * @param _witness - Address of the witness
     * @param _data - Bytes of the order's data
     * @return bytes32 - order's key
     */
    function keyOf(
        IModule _module,
        IERC20 _inputToken,
        address payable _owner,
        address _witness,
        bytes memory _data
    ) public pure returns (bytes32) {
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