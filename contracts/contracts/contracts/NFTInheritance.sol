// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/**
 * @title NFTInheritance
 * @dev Specialized inheritance contract for NFTs with collection management
 * @author Navidbiz1
 */
contract NFTInheritance {
    address public owner;
    address public heir;
    uint256 public lastActiveTimestamp;
    uint256 public constant INACTIVITY_PERIOD = 90 days;
    
    struct NFTAsset {
        address contractAddress;
        uint256 tokenId;
        bool isERC1155;
        uint256 amount; // For ERC1155
        string metadata;
    }
    
    NFTAsset[] public nftAssets;
    mapping(address => mapping(uint256 => bool)) public nftRegistered;
    mapping(address => bool) public approvedCollections;
    
    event NFTAdded(address indexed contractAddress, uint256 indexed tokenId, bool isERC1155);
    event NFTTransferred(address indexed contractAddress, uint256 indexed tokenId, address indexed heir);
    event CollectionApproved(address indexed contractAddress);
    event CollectionRevoked(address indexed contractAddress);
    event InheritanceActivated(address indexed heir);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "NFTInheritance: caller is not owner");
        _;
    }
    
    modifier onlyHeir() {
        require(msg.sender == heir, "NFTInheritance: caller is not heir");
        _;
    }
    
    modifier inheritanceAvailable() {
        require(
            block.timestamp > lastActiveTimestamp + INACTIVITY_PERIOD,
            "NFTInheritance: inheritance not yet available"
        );
        _;
    }

    constructor(address _heir) {
        require(_heir != address(0), "NFTInheritance: heir cannot be zero address");
        owner = msg.sender;
        heir = _heir;
        lastActiveTimestamp = block.timestamp;
    }
    
    /**
     * @dev Update proof of life timestamp
     */
    function proveAlive() external onlyOwner {
        lastActiveTimestamp = block.timestamp;
    }
    
    /**
     * @dev Add an NFT to inheritance management
     */
    function addNFT(
        address _contractAddress,
        uint256 _tokenId,
        bool _isERC1155,
        uint256 _amount,
        string memory _metadata
    ) external onlyOwner {
        require(_contractAddress != address(0), "NFTInheritance: invalid contract address");
        require(!nftRegistered[_contractAddress][_tokenId], "NFTInheritance: NFT already registered");
        
        // Verify ownership
        if (_isERC1155) {
            IERC1155 nftContract = IERC1155(_contractAddress);
            require(
                nftContract.balanceOf(owner, _tokenId) >= _amount,
                "NFTInheritance: insufficient ERC1155 balance"
            );
        } else {
            IERC721 nftContract = IERC721(_contractAddress);
            require(
                nftContract.ownerOf(_tokenId) == owner,
                "NFTInheritance: not owner of ERC721"
            );
        }
        
        nftAssets.push(NFTAsset({
            contractAddress: _contractAddress,
            tokenId: _tokenId,
            isERC1155: _isERC1155,
            amount: _amount,
            metadata: _metadata
        }));
        
        nftRegistered[_contractAddress][_tokenId] = true;
        emit NFTAdded(_contractAddress, _tokenId, _isERC1155);
    }
    
    /**
     * @dev Approve an entire NFT collection for inheritance
     */
    function approveCollection(address _contractAddress) external onlyOwner {
        require(_contractAddress != address(0), "NFTInheritance: invalid contract address");
        approvedCollections[_contractAddress] = true;
        emit CollectionApproved(_contractAddress);
    }
    
    /**
     * @dev Revoke collection approval
     */
    function revokeCollection(address _contractAddress) external onlyOwner {
        approvedCollections[_contractAddress] = false;
        emit CollectionRevoked(_contractAddress);
    }
    
    /**
     * @dev Claim NFT inheritance
     */
    function claimNFTInheritance() external onlyHeir inheritanceAvailable {
        require(nftAssets.length > 0, "NFTInheritance: no NFTs to inherit");
        
        for (uint256 i = 0; i < nftAssets.length; i++) {
            NFTAsset memory asset = nftAssets[i];
            
            if (asset.isERC1155) {
                IERC1155 nftContract = IERC1155(asset.contractAddress);
                nftContract.safeTransferFrom(
                    owner,
                    heir,
                    asset.tokenId,
                    asset.amount,
                    ""
                );
            } else {
                IERC721 nftContract = IERC721(asset.contractAddress);
                nftContract.safeTransferFrom(owner, heir, asset.tokenId);
            }
            
            emit NFTTransferred(asset.contractAddress, asset.tokenId, heir);
        }
        
        // Clear the assets array after transfer
        delete nftAssets;
        emit InheritanceActivated(heir);
    }
    
    /**
     * @dev Batch transfer approved collection NFTs
     */
    function claimCollectionInheritance(address _contractAddress) external onlyHeir inheritanceAvailable {
        require(approvedCollections[_contractAddress], "NFTInheritance: collection not approved");
        
        IERC721 nftContract = IERC721(_contractAddress);
        // This would require additional logic to handle multiple tokens
        // For simplicity, we're showing the concept
        
        emit CollectionApproved(_contractAddress);
    }
    
    /**
     * @dev Remove NFT from inheritance management
     */
    function removeNFT(address _contractAddress, uint256 _tokenId) external onlyOwner {
        require(nftRegistered[_contractAddress][_tokenId], "NFTInheritance: NFT not registered");
        
        for (uint256 i = 0; i < nftAssets.length; i++) {
            if (nftAssets[i].contractAddress == _contractAddress && nftAssets[i].tokenId == _tokenId) {
                nftAssets[i] = nftAssets[nftAssets.length - 1];
                nftAssets.pop();
                break;
            }
        }
        
        nftRegistered[_contractAddress][_tokenId] = false;
    }
    
    /**
     * @dev Get total NFT count
     */
    function getNFTCount() external view returns (uint256) {
        return nftAssets.length;
    }
    
    /**
     * @dev Get NFT details by index
     */
    function getNFT(uint256 index) external view returns (NFTAsset memory) {
        require(index < nftAssets.length, "NFTInheritance: index out of bounds");
        return nftAssets[index];
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
     * @dev Change heir address
     */
    function changeHeir(address _newHeir) external onlyOwner {
        require(_newHeir != address(0), "NFTInheritance: new heir cannot be zero address");
        heir = _newHeir;
    }
    
    /**
     * @dev Check if collection is approved
     */
    function isCollectionApproved(address _contractAddress) external view returns (bool) {
        return approvedCollections[_contractAddress];
    }
    
    /**
     * @dev Emergency function to rescue NFTs if something goes wrong
     */
    function emergencyWithdrawNFT(
        address _contractAddress,
        uint256 _tokenId,
        bool _isERC1155,
        uint256 _amount
    ) external onlyOwner {
        require(block.timestamp < lastActiveTimestamp + INACTIVITY_PERIOD, "NFTInheritance: inheritance period active");
        
        if (_isERC1155) {
            IERC1155 nftContract = IERC1155(_contractAddress);
            nftContract.safeTransferFrom(address(this), owner, _tokenId, _amount, "");
        } else {
            IERC721 nftContract = IERC721(_contractAddress);
            nftContract.safeTransferFrom(address(this), owner, _tokenId);
        }
    }
}
