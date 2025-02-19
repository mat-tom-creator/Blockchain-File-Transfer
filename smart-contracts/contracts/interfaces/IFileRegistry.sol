// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../libraries/FileStructs.sol";

/**
 * @title IFileRegistry
 * @dev Interface for the FileRegistry contract
 */
interface IFileRegistry {
    /**
     * @dev Registers a new file in the system
     * @param name File name
     * @param contentHash Hash of the file content
     * @param encryptionKey Encrypted symmetric key
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
    ) external returns (bytes32 fileId);
    
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
    ) external;
    
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
    ) external;
    
    /**
     * @dev Revokes access to a file for a specific user
     * @param fileId File identifier
     * @param grantee Address to revoke access from
     */
    function revokeAccess(bytes32 fileId, address grantee) external;
    
    /**
     * @dev Logical deletion of a file
     * @param fileId File identifier to delete
     */
    function deleteFile(bytes32 fileId) external;
    
    /**
     * @dev Gets file metadata
     * @param fileId File identifier
     * @return File metadata
     */
    function getFileMetadata(bytes32 fileId) 
        external 
        view 
        returns (FileStructs.FileMetadataView memory);
    
    /**
     * @dev Gets list of files owned by a user
     * @param owner Address of the file owner
     * @return Array of file identifiers
     */
    function getUserFiles(address owner) 
        external 
        view 
        returns (bytes32[] memory);
    
    /**
     * @dev Checks if user has specific access to a file
     * @param fileId File identifier
     * @param user User address to check
     * @param level Access level to check
     * @return True if user has the specified access level
     */
    function checkAccess(
        bytes32 fileId,
        address user,
        FileStructs.AccessLevel level
    ) external view returns (bool);
}