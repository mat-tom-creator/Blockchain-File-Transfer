// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./FileStructs.sol";

/**
 * @title TransferStructs
 * @dev Library defining transfer-related data structures
 */
library TransferStructs {
    
    /**
     * @dev Enum defining possible transfer statuses
     */
    enum TransferStatus {
        NONE,       // 0: Invalid/uninitialized
        INITIATED,  // 1: Transfer has been initiated but not yet accepted
        IN_PROGRESS,// 2: Transfer has been accepted and is in progress
        COMPLETED,  // 3: Transfer has been completed successfully
        REJECTED,   // 4: Transfer was rejected by recipient
        CANCELLED,  // 5: Transfer was cancelled by sender
        DISPUTED,   // 6: Transfer is under dispute
        EXPIRED     // 7: Transfer expired before acceptance
    }
    
    /**
     * @dev Enum defining possible dispute resolutions
     */
    enum Resolution {
        NONE,       // 0: No resolution yet
        COMPLETED,  // 1: Resolved as completed
        CANCELLED   // 2: Resolved as cancelled
    }
    
    /**
     * @dev Structure for transfer storage
     */
    struct Transfer {
        bytes32 transferId;            // Unique identifier
        bytes32 fileId;                // ID of file being transferred
        address sender;                // Address initiating the transfer
        address recipient;             // Address receiving the transfer
        string message;                // Optional message to recipient
        uint256 initiatedAt;           // When transfer was initiated
        uint256 deadline;              // When transfer expires
        uint256 completedAt;           // When transfer was completed (0 if not completed)
        TransferStatus status;         // Current status
        FileStructs.AccessLevel accessLevel; // Access level to grant upon completion
        bytes32 proofOfDelivery;       // Cryptographic proof of successful transfer
        string disputeReason;          // Reason if disputed
        Resolution resolution;         // Resolution if disputed
    }
    
    /**
     * @dev Structure for transfer view (return type)
     */
    struct TransferView {
        bytes32 transferId;
        bytes32 fileId;
        address sender;
        address recipient;
        string message;
        uint256 initiatedAt;
        uint256 deadline;
        uint256 completedAt;
        TransferStatus status;
        FileStructs.AccessLevel accessLevel;
        bytes32 proofOfDelivery;
        string disputeReason;
        Resolution resolution;
    }
    
    /**
     * @dev Structure for transfer statistics
     */
    struct TransferStats {
        uint256 totalInitiated;
        uint256 totalCompleted;
        uint256 totalRejected;
        uint256 totalCancelled;
        uint256 totalDisputed;
        uint256 totalExpired;
        uint256 averageCompletionTime;  // In seconds
    }
    
    /**
     * @dev Structure for batch transfer
     */
    struct BatchTransfer {
        bytes32 batchId;
        bytes32[] transferIds;
        address sender;
        address[] recipients;
        uint256 initiatedAt;
        uint256 completedCount;
        bool allCompleted;
    }
    
    /**
     * @dev Structure for transfer notification
     */
    struct TransferNotification {
        bytes32 transferId;
        bytes32 fileId;
        address sender;
        address recipient;
        string message;
        uint256 timestamp;
        bool isRead;
    }
}