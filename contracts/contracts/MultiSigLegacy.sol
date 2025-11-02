// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title MultiSigLegacy
 * @dev Multi-signature wallet for family inheritance with time-lock features
 * @author Navidbiz1
 */
contract MultiSigLegacy {
    address[] public owners;
    mapping(address => bool) public isOwner;
    uint256 public required;
    uint256 public constant INACTIVITY_PERIOD = 90 days;
    uint256 public lastActivityTime;
    
    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint256 confirmations;
    }
    
    mapping(uint256 => mapping(address => bool)) public confirmations;
    Transaction[] public transactions;
    
    event Deposit(address indexed sender, uint256 amount);
    event Submission(uint256 indexed transactionId);
    event Confirmation(address indexed sender, uint256 indexed transactionId);
    event Execution(uint256 indexed transactionId);
    event ExecutionFailure(uint256 indexed transactionId);
    event OwnerAddition(address indexed owner);
    event OwnerRemoval(address indexed owner);
    event RequirementChange(uint256 required);
    
    modifier onlyWallet() {
        require(msg.sender == address(this), "MultiSig: caller must be wallet itself");
        _;
    }
    
    modifier ownerDoesNotExist(address owner) {
        require(!isOwner[owner], "MultiSig: owner already exists");
        _;
    }
    
    modifier ownerExists(address owner) {
        require(isOwner[owner], "MultiSig: owner does not exist");
        _;
    }
    
    modifier transactionExists(uint256 transactionId) {
        require(transactionId < transactions.length, "MultiSig: transaction does not exist");
        _;
    }
    
    modifier confirmed(uint256 transactionId, address owner) {
        require(confirmations[transactionId][owner], "MultiSig: transaction not confirmed");
        _;
    }
    
    modifier notConfirmed(uint256 transactionId, address owner) {
        require(!confirmations[transactionId][owner], "MultiSig: transaction already confirmed");
        _;
    }
    
    modifier notExecuted(uint256 transactionId) {
        require(!transactions[transactionId].executed, "MultiSig: transaction already executed");
        _;
    }
    
    modifier validRequirement(uint256 ownerCount, uint256 _required) {
        require(_required <= ownerCount && _required > 0 && ownerCount > 0, "MultiSig: invalid requirements");
        _;
    }

    /**
     * @dev Contract constructor sets initial owners and required number of confirmations
     * @param _owners List of initial owners
     * @param _required Number of required confirmations
     */
    constructor(address[] memory _owners, uint256 _required) 
        validRequirement(_owners.length, _required) 
    {
        for (uint256 i = 0; i < _owners.length; i++) {
            require(_owners[i] != address(0) && !isOwner[_owners[i]], "MultiSig: invalid owner");
            isOwner[_owners[i]] = true;
            owners.push(_owners[i]);
        }
        required = _required;
        lastActivityTime = block.timestamp;
    }
    
    /**
     * @dev Allows to add a new owner. Transaction has to be sent by wallet
     * @param owner Address of new owner
     */
    function addOwner(address owner)
        external
        onlyWallet
        ownerDoesNotExist(owner)
        validRequirement(owners.length + 1, required)
    {
        isOwner[owner] = true;
        owners.push(owner);
        emit OwnerAddition(owner);
    }
    
    /**
     * @dev Allows to remove an owner. Transaction has to be sent by wallet
     * @param owner Address of owner to remove
     */
    function removeOwner(address owner)
        external
        onlyWallet
        ownerExists(owner)
    {
        isOwner[owner] = false;
        for (uint256 i = 0; i < owners.length - 1; i++) {
            if (owners[i] == owner) {
                owners[i] = owners[owners.length - 1];
                break;
            }
        }
        owners.pop();
        if (required > owners.length) {
            changeRequirement(owners.length);
        }
        emit OwnerRemoval(owner);
    }
    
    /**
     * @dev Allows to replace an owner with a new owner. Transaction has to be sent by wallet
     * @param owner Address of owner to be replaced
     * @param newOwner Address of new owner
     */
    function replaceOwner(address owner, address newOwner)
        external
        onlyWallet
        ownerExists(owner)
        ownerDoesNotExist(newOwner)
    {
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == owner) {
                owners[i] = newOwner;
                break;
            }
        }
        isOwner[owner] = false;
        isOwner[newOwner] = true;
        emit OwnerRemoval(owner);
        emit OwnerAddition(newOwner);
    }
    
    /**
     * @dev Allows to change the number of required confirmations. Transaction has to be sent by wallet
     * @param _required Number of required confirmations
     */
    function changeRequirement(uint256 _required)
        public
        onlyWallet
        validRequirement(owners.length, _required)
    {
        required = _required;
        emit RequirementChange(_required);
    }
    
    /**
     * @dev Allows an owner to submit and confirm a transaction
     * @param destination Transaction target address
     * @param value Transaction ether value
     * @param data Transaction data payload
     * @return transactionId Transaction ID
     */
    function submitTransaction(address destination, uint256 value, bytes memory data)
        external
        ownerExists(msg.sender)
        returns (uint256 transactionId)
    {
        transactionId = addTransaction(destination, value, data);
        confirmTransaction(transactionId);
    }
    
    /**
     * @dev Allows an owner to confirm a transaction
     * @param transactionId Transaction ID
     */
    function confirmTransaction(uint256 transactionId)
        public
        ownerExists(msg.sender)
        transactionExists(transactionId)
        notConfirmed(transactionId, msg.sender)
    {
        confirmations[transactionId][msg.sender] = true;
        transactions[transactionId].confirmations++;
        emit Confirmation(msg.sender, transactionId);
        executeTransaction(transactionId);
    }
    
    /**
     * @dev Allows an owner to revoke a confirmation for a transaction
     * @param transactionId Transaction ID
     */
    function revokeConfirmation(uint256 transactionId)
        external
        ownerExists(msg.sender)
        confirmed(transactionId, msg.sender)
        notExecuted(transactionId)
    {
        confirmations[transactionId][msg.sender] = false;
        transactions[transactionId].confirmations--;
    }
    
    /**
     * @dev Allows anyone to execute a confirmed transaction
     * @param transactionId Transaction ID
     */
    function executeTransaction(uint256 transactionId)
        public
        ownerExists(msg.sender)
        confirmed(transactionId, msg.sender)
        notExecuted(transactionId)
    {
        if (isConfirmed(transactionId)) {
            Transaction storage txn = transactions[transactionId];
            txn.executed = true;
            (bool success, ) = txn.to.call{value: txn.value}(txn.data);
            if (success) {
                emit Execution(transactionId);
            } else {
                emit ExecutionFailure(transactionId);
                txn.executed = false;
            }
        }
    }
    
    /**
     * @dev Returns the confirmation status of a transaction
     * @param transactionId Transaction ID
     * @return bool Confirmation status
     */
    function isConfirmed(uint256 transactionId) public view returns (bool) {
        return transactions[transactionId].confirmations >= required;
    }
    
    /**
     * @dev Adds a new transaction to the transaction list
     * @param destination Transaction target address
     * @param value Transaction ether value
     * @param data Transaction data payload
     * @return transactionId Transaction ID
     */
    function addTransaction(address destination, uint256 value, bytes memory data)
        internal
        returns (uint256 transactionId)
    {
        transactionId = transactions.length;
        transactions.push(Transaction({
            to: destination,
            value: value,
            data: data,
            executed: false,
            confirmations: 0
        }));
        emit Submission(transactionId);
    }
    
    /**
     * @dev Returns number of confirmations of a transaction
     * @param transactionId Transaction ID
     * @return count Number of confirmations
     */
    function getConfirmationCount(uint256 transactionId) external view returns (uint256 count) {
        return transactions[transactionId].confirmations;
    }
    
    /**
     * @dev Returns total number of transactions after filers are applied
     * @param pending Include pending transactions
     * @param executed Include executed transactions
     * @return count Total number of transactions
     */
    function getTransactionCount(bool pending, bool executed) external view returns (uint256 count) {
        for (uint256 i = 0; i < transactions.length; i++) {
            if (pending && !transactions[i].executed || executed && transactions[i].executed) {
                count++;
            }
        }
    }
    
    /**
     * @dev Returns list of owners
     * @return List of owner addresses
     */
    function getOwners() external view returns (address[] memory) {
        return owners;
    }
    
    /**
     * @dev Returns array with owner addresses, which confirmed transaction
     * @param transactionId Transaction ID
     * @return _confirmations Array of owner addresses
     */
    function getConfirmations(uint256 transactionId) external view returns (address[] memory _confirmations) {
        address[] memory confirmationsTemp = new address[](owners.length);
        uint256 count = 0;
        uint256 i;
        for (i = 0; i < owners.length; i++) {
            if (confirmations[transactionId][owners[i]]) {
                confirmationsTemp[count] = owners[i];
                count++;
            }
        }
        _confirmations = new address[](count);
        for (i = 0; i < count; i++) {
            _confirmations[i] = confirmationsTemp[i];
        }
    }
    
    /**
     * @dev Returns the inactivity period
     * @return Time since last activity
     */
    function getInactivityPeriod() external view returns (uint256) {
        return block.timestamp - lastActivityTime;
    }
    
    /**
     * @dev Update activity timestamp
     */
    function updateActivity() external ownerExists(msg.sender) {
        lastActivityTime = block.timestamp;
    }
    
    // Fallback function allows to deposit ether
    receive() external payable {
        if (msg.value > 0) {
            emit Deposit(msg.sender, msg.value);
        }
    }
}
