// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title LegacyWallet
 * @dev Secure inheritance wallet with time-lock and multi-sig features
 * @author Navidbiz1
 */
contract LegacyWallet {
    address public owner;
    address public heir;
    uint256 public lastActiveTimestamp;
    uint256 public constant INACTIVITY_PERIOD = 90 days;
    
    mapping(address => bool) public guardians;
    uint256 public guardianCount;
    uint256 public requiredGuardians;
    
    event InheritanceInitiated(address indexed heir, uint256 amount);
    event InheritanceClaimed(address indexed heir, uint256 amount);
    event ProofOfLife(address indexed owner);
    event GuardianAdded(address indexed guardian);
    event GuardianRemoved(address indexed guardian);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "LegacyWallet: caller is not owner");
        _;
    }
    
    modifier onlyHeir() {
        require(msg.sender == heir, "LegacyWallet: caller is not heir");
        _;
    }
    
    modifier onlyGuardian() {
        require(guardians[msg.sender], "LegacyWallet: caller is not guardian");
        _;
    }

    constructor(
        address _heir,
        address[] memory _guardians,
        uint256 _requiredGuardians
    ) payable {
        require(_heir != address(0), "LegacyWallet: heir cannot be zero address");
        require(_guardians.length >= _requiredGuardians, "LegacyWallet: insufficient guardians");
        require(_requiredGuardians > 0, "LegacyWallet: required guardians must be positive");
        
        owner = msg.sender;
        heir = _heir;
        lastActiveTimestamp = block.timestamp;
        requiredGuardians = _requiredGuardians;
        
        for (uint i = 0; i < _guardians.length; i++) {
            require(_guardians[i] != address(0), "LegacyWallet: guardian cannot be zero address");
            guardians[_guardians[i]] = true;
            guardianCount++;
        }
    }
    
    /**
     * @dev Update proof of life timestamp
     */
    function proveAlive() external onlyOwner {
        lastActiveTimestamp = block.timestamp;
        emit ProofOfLife(owner);
    }
    
    /**
     * @dev Initiate inheritance process (requires guardian approval)
     */
    function initiateInheritance() external onlyGuardian {
        require(
            block.timestamp > lastActiveTimestamp + INACTIVITY_PERIOD,
            "LegacyWallet: owner still active"
        );
        
        uint256 inheritance = address(this).balance;
        require(inheritance > 0, "LegacyWallet: no funds to inherit");
        
        emit InheritanceInitiated(heir, inheritance);
    }
    
    /**
     * @dev Claim inheritance after guardian initiation
     */
    function claimInheritance() external onlyHeir {
        require(
            block.timestamp > lastActiveTimestamp + INACTIVITY_PERIOD,
            "LegacyWallet: inheritance not yet available"
        );
        
        uint256 inheritance = address(this).balance;
        require(inheritance > 0, "LegacyWallet: no funds to inherit");
        
        // Transfer all ETH to heir
        (bool success, ) = payable(heir).call{value: inheritance}("");
        require(success, "LegacyWallet: transfer failed");
        
        emit InheritanceClaimed(heir, inheritance);
    }
    
    /**
     * @dev Add a new guardian
     */
    function addGuardian(address _guardian) external onlyOwner {
        require(_guardian != address(0), "LegacyWallet: guardian cannot be zero address");
        require(!guardians[_guardian], "LegacyWallet: already a guardian");
        
        guardians[_guardian] = true;
        guardianCount++;
        emit GuardianAdded(_guardian);
    }
    
    /**
     * @dev Remove a guardian
     */
    function removeGuardian(address _guardian) external onlyOwner {
        require(guardians[_guardian], "LegacyWallet: not a guardian");
        require(guardianCount > requiredGuardians, "LegacyWallet: cannot remove below required");
        
        guardians[_guardian] = false;
        guardianCount--;
        emit GuardianRemoved(_guardian);
    }
    
    /**
     * @dev Change heir address
     */
    function changeHeir(address _newHeir) external onlyOwner {
        require(_newHeir != address(0), "LegacyWallet: new heir cannot be zero address");
        heir = _newHeir;
    }
    
    /**
     * @dev Get time remaining until inheritance can be claimed
     */
    function getTimeUntilInheritance() external view returns (uint256) {
        if (block.timestamp <= lastActiveTimestamp + INACTIVITY_PERIOD) {
            return (lastActiveTimestamp + INACTIVITY_PERIOD) - block.timestamp;
        }
        return 0;
    }
    
    /**
     * @dev Get contract balance
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    /**
     * @dev Get guardian status
     */
    function isGuardian(address _address) external view returns (bool) {
        return guardians[_address];
    }
    
    // Allow contract to receive ETH
    receive() external payable {}
    fallback() external payable {}
}
