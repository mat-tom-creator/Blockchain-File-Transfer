// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/IFileRegistry.sol";
import "./libraries/FileStructs.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title FileRegistry
 * @dev Manages file metadata and ownership records on the blockchain
 */
contract FileRegistry is IFileRegistry, AccessControl, ReentrancyGuard, Pausable {
    using Counters for Counters.Counter;
    
    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    // State variables
    mapping(bytes32 => FileStructs.FileMetadata) private _files;
    mapping(address => bytes32[]) private _userFiles;
    mapping(bytes32 => mapping(address => FileStructs.AccessPermission)) private _filePermissions;
    
    Counters.Counter private _fileIdCounter;
    uint256 public maxFileSize;
    
    // Events
    event FileRegistered(bytes32 indexed fileId, address indexed owner, bytes32 contentHash);
    event FileUpdated(bytes32 indexed fileId, bytes32 newContentHash);
    event FileAccessGranted(bytes32 indexed fileId, address indexed grantee, FileStructs.AccessLevel accessLevel);
    event FileAccessRevoked(bytes32 indexed fileId, address indexed grantee);
    event FileDeleted(bytes32 indexed fileId);
    
    /**
     * @dev Constructor
     * @param initialAdmin Address of the initial admin
     * @param initialMaxFileSize Maximum allowed file size in bytes
     */
    constructor(address initialAdmin, uint256 initialMaxFileSize) {
        _setupRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _setupRole(ADMIN_ROLE, initialAdmin);
        maxFileSize = initialMaxFileSize;
    }
    
    /**
     * @dev Modifier to check if caller has access to file
     * @param fileId File identifier
     * @param requiredLevel Minimum access level required
     */
    modifier hasFileAccess(bytes32 fileId, FileStructs.AccessLevel requiredLevel) {
        require(_files[fileId].exists, "File does not exist");
        
        if (_files[fileId].owner == msg.sender) {
            // Owner has full access
            _;
            return;
        }
        
        FileStructs.AccessPermission memory permission = _filePermissions[fileId][msg.sender];
        require(permission.hasAccess, "Access denied");
        require(uint8(permission.level) >= uint8(requiredLevel), "Insufficient access level");
        require(block.timestamp <= permission.expiresAt || permission.expiresAt == 0, "Access expired");
        
        _;
    }
    
    /**
     * @dev Registers a new file in the system
     * @param name File name
     * @param contentHash Hash of the file content (IPFS CID or other content identifier)
     * @param encryptionKey Encrypted symmetric key (encrypted with owner's public key)
     * @param fileSize Size of file in bytes
     * @param contentType MIME type of the file
     * @param isPublic Whether file is publicly accessible
     * @return fileId Unique identifier for the file
     */
    function registerFile(
        string memory name,
        bytes32 contentHash,
        bytes memory encryptionKey,
        uint256 fileSize,
        string memory contentType,
        bool isPublic
    ) 
        external 
        whenNotPaused
        nonReentrant
        returns (bytes32 fileId)
    {
        require(fileSize > 0 && fileSize <= maxFileSize, "Invalid file size");
        require(bytes(name).length > 0, "Name cannot be empty");
        
        // Generate a unique file ID
        _fileIdCounter.increment();
        fileId = keccak256(abi.encodePacked(
            msg.sender,
            _fileIdCounter.current(),
            block.timestamp,
            contentHash
        ));
        
        // Create and store file metadata
        FileStructs.FileMetadata memory newFile = FileStructs.FileMetadata({
            fileId: fileId,
            name: name,
            owner: msg.sender,
            contentHash: contentHash,
            encryptionKey: encryptionKey,
            fileSize: fileSize,
            contentType: contentType,
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            isPublic: isPublic,
            isDeleted: false,
            exists: true
        });
        
        _files[fileId] = newFile;
        _userFiles[msg.sender].push(fileId);
        
        emit FileRegistered(fileId, msg.sender, contentHash);
        return fileId;
    }
    
    /**
     * @dev Updates an existing file's content
     * @param fileId Identifier of file to update
     * @param newContentHash New content hash of the file
     * @param newEncryptionKey New encryption key (if changed)
     * @param newFileSize New file size in bytes
     */
    function updateFile(
        bytes32 fileId,
        bytes32 newContentHash,
        bytes memory newEncryptionKey,
        uint256 newFileSize
    ) 
        external 
        whenNotPaused
        nonReentrant
        hasFileAccess(fileId, FileStructs.AccessLevel.WRITE)
    {
        require(newFileSize > 0 && newFileSize <= maxFileSize, "Invalid file size");
        
        FileStructs.FileMetadata storage file = _files[fileId];
        
        // Only owner can change encryption key
        if (msg.sender != file.owner) {
            require(newEncryptionKey.length == 0, "Only owner can change encryption key");
        }
        
        file.contentHash = newContentHash;
        if (newEncryptionKey.length > 0) {
            file.encryptionKey = newEncryptionKey;
        }
        file.fileSize = newFileSize;
        file.updatedAt = block.timestamp;
        
        emit FileUpdated(fileId, newContentHash);
    }
    
    /**
     * @dev Grants access to a file for a specific user
     * @param fileId File identifier
     * @param grantee Address to grant access to
     * @param accessLevel Level of access to grant
     * @param expiresAt Timestamp when access expires (0 for no expiration)
     */
    function grantAccess(
        bytes32 fileId,
        address grantee,
        FileStructs.AccessLevel accessLevel,
        uint256 expiresAt
    ) 
        external 
        whenNotPaused
        nonReentrant
    {
        require(_files[fileId].exists, "File does not exist");
        require(_files[fileId].owner == msg.sender, "Only owner can grant access");
        require(grantee != address(0), "Invalid grantee address");
        require(grantee != msg.sender, "Cannot grant access to self");
        
        _filePermissions[fileId][grantee] = FileStructs.AccessPermission({
            hasAccess: true,
            level: accessLevel,
            grantedAt: block.timestamp,
            expiresAt: expiresAt
        });
        
        emit FileAccessGranted(fileId, grantee, accessLevel);
    }
    
    /**
     * @dev Revokes access to a file for a specific user
     * @param fileId File identifier
     * @param grantee Address to revoke access from
     */
    function revokeAccess(bytes32 fileId, address grantee) 
        external 
        whenNotPaused
        nonReentrant
    {
        require(_files[fileId].exists, "File does not exist");
        require(_files[fileId].owner == msg.sender, "Only owner can revoke access");
        require(_filePermissions[fileId][grantee].hasAccess, "No access to revoke");
        
        delete _filePermissions[fileId][grantee];
        
        emit FileAccessRevoked(fileId, grantee);
    }
    
    /**
     * @dev Logical deletion of a file
     * @param fileId File identifier to delete
     */
    function deleteFile(bytes32 fileId) 
        external 
        whenNotPaused
        nonReentrant
    {
        require(_files[fileId].exists, "File does not exist");
        require(_files[fileId].owner == msg.sender || hasRole(ADMIN_ROLE, msg.sender), "Not authorized");
        
        _files[fileId].isDeleted = true;
        
        emit FileDeleted(fileId);
    }
    
    /**
     * @dev Gets file metadata
     * @param fileId File identifier
     * @return File metadata
     */
    function getFileMetadata(bytes32 fileId) 
        external 
        view 
        returns (FileStructs.FileMetadataView memory)
    {
        FileStructs.FileMetadata storage file = _files[fileId];
        
        require(file.exists, "File does not exist");
        
        // Check access for non-public files
        if (!file.isPublic) {
            bool hasAccess = file.owner == msg.sender || 
                             hasRole(ADMIN_ROLE, msg.sender) ||
                             (_filePermissions[fileId][msg.sender].hasAccess && 
                              (block.timestamp <= _filePermissions[fileId][msg.sender].expiresAt || 
                               _filePermissions[fileId][msg.sender].expiresAt == 0));
            require(hasAccess, "Access denied");
        }
        
        // Return view without encryption key for non-owners
        bool includeKey = file.owner == msg.sender;
        
        return FileStructs.FileMetadataView({
            fileId: file.fileId,
            name: file.name,
            owner: file.owner,
            contentHash: file.contentHash,
            encryptionKey: includeKey ? file.encryptionKey : bytes(""),
            fileSize: file.fileSize,
            contentType: file.contentType,
            createdAt: file.createdAt,
            updatedAt: file.updatedAt,
            isPublic: file.isPublic,
            isDeleted: file.isDeleted
        });
    }
    
    /**
     * @dev Gets list of files owned by a user
     * @param owner Address of the file owner
     * @return Array of file identifiers
     */
    function getUserFiles(address owner) 
        external 
        view 
        returns (bytes32[] memory)
    {
        return _userFiles[owner];
    }
    
    /**
     * @dev Checks if user has specific access to a file
     * @param fileId File identifier
     * @param user User address to check
     * @param level Access level to check
     * @return True if user has the specified access level
     */
    function checkAccess(bytes32 fileId, address user, FileStructs.AccessLevel level) 
        external 
        view 
        returns (bool)
    {
        if (!_files[fileId].exists || _files[fileId].isDeleted) {
            return false;
        }
        
        // Owner has all access levels
        if (_files[fileId].owner == user) {
            return true;
        }
        
        // Public files have READ access for everyone
        if (_files[fileId].isPublic && level == FileStructs.AccessLevel.READ) {
            return true;
        }
        
        // Check explicit permissions
        FileStructs.AccessPermission memory permission = _filePermissions[fileId][user];
        if (!permission.hasAccess) {
            return false;
        }
        
        // Check permission expiration
        if (permission.expiresAt != 0 && block.timestamp > permission.expiresAt) {
            return false;
        }
        
        // Check permission level
        return uint8(permission.level) >= uint8(level);
    }
    
    /**
     * @dev Sets the maximum allowed file size
     * @param newMaxFileSize New maximum file size in bytes
     */
    function setMaxFileSize(uint256 newMaxFileSize) 
        external 
        onlyRole(ADMIN_ROLE)
    {
        maxFileSize = newMaxFileSize;
    }
    
    /**
     * @dev Pauses contract operations
     */
    function pause() 
        external 
        onlyRole(ADMIN_ROLE)
    {
        _pause();
    }
    
    /**
     * @dev Unpauses contract operations
     */
    function unpause() 
        external 
        onlyRole(ADMIN_ROLE)
    {
        _unpause();
    }
}