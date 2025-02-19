// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title FileStructs
 * @dev Library defining file-related data structures
 */
library FileStructs {
    
    /**
     * @dev Enum defining access levels for file permissions
     */
    enum AccessLevel {
        NONE,       // 0: No access
        READ,       // 1: Read-only access
        WRITE,      // 2: Read and write access
        ADMIN       // 3: Full control including access management
    }
    
    /**
     * @dev Structure for file metadata storage
     */
    struct FileMetadata {
        bytes32 fileId;           // Unique identifier
        string name;              // File name
        address owner;            // File owner's address
        bytes32 contentHash;      // Content identifier (IPFS CID or other hash)
        bytes encryptionKey;      // Encrypted symmetric key
        uint256 fileSize;         // File size in bytes
        string contentType;       // MIME type
        uint256 createdAt;        // Creation timestamp
        uint256 updatedAt;        // Last update timestamp
        bool isPublic;            // Whether file is publicly accessible
        bool isDeleted;           // Logical deletion flag
        bool exists;              // Existence flag to distinguish null entries
    }
    
    /**
     * @dev Structure for file metadata view (return type)
     * Separates storage and view concerns
     */
    struct FileMetadataView {
        bytes32 fileId;
        string name;
        address owner;
        bytes32 contentHash;
        bytes encryptionKey;      // Empty for non-owners
        uint256 fileSize;
        string contentType;
        uint256 createdAt;
        uint256 updatedAt;
        bool isPublic;
        bool isDeleted;
    }
    
    /**
     * @dev Structure for file version
     */
    struct FileVersion {
        bytes32 versionId;
        bytes32 fileId;
        bytes32 contentHash;
        bytes encryptionKey;
        uint256 fileSize;
        uint256 createdAt;
        address creator;
        string changeDescription;
    }
    
    /**
     * @dev Structure for access permissions
     */
    struct AccessPermission {
        bool hasAccess;           // Whether access is granted
        AccessLevel level;        // Level of access
        uint256 grantedAt;        // When access was granted
        uint256 expiresAt;        // When access expires (0 for no expiration)
    }
    
    /**
     * @dev Structure for file chunk
     * Used for large file handling
     */
    struct FileChunk {
        bytes32 chunkId;
        bytes32 fileId;
        uint256 sequence;
        bytes32 contentHash;
        uint256 size;
    }
    
    /**
     * @dev Structure for file storage location
     */
    struct StorageLocation {
        bytes32 fileId;
        string protocol;          // e.g., "ipfs", "swarm", "arweave"
        string location;          // Protocol-specific location identifier
        bool isEncrypted;
        string encryptionType;    // e.g., "aes256-gcm"
    }
}