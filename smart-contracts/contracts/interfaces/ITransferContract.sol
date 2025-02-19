// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../libraries/TransferStructs.sol";
import "../libraries/FileStructs.sol";

/**
 * @title ITransferContract
 * @dev Interface for the TransferContract
 */
interface ITransferContract {
    /**
     * @dev Initiates a new file transfer
     * @param fileId File identifier to transfer
     * @param recipient Address of the recipient
     * @param message Optional message to recipient
     * @param transferDeadline Optional deadline for the transfer (0 for default)
     * @param accessLevel Access level to grant to recipient upon acceptance
     * @return transferId Unique identifier for the transfer
     */
    function initiateTransfer(
        bytes32 fileId,
        address recipient,
        string memory message,
        uint256 transferDeadline,
        FileStructs.AccessLevel accessLevel
    ) external returns (bytes32 transferId);
    
    /**
     * @dev Cancels a pending transfer (sender only)
     * @param transferId Transfer identifier to cancel
     */
    function cancelTransfer(bytes32 transferId) external;
    
    /**
     * @dev Accepts a pending transfer (recipient only)
     * @param transferId Transfer identifier to accept
     */
    function acceptTransfer(bytes32 transferId) external;
    
    /**
     * @dev Rejects a pending transfer (recipient only)
     * @param transferId Transfer identifier to reject
     * @param reason Reason for rejection
     */
    function rejectTransfer(bytes32 transferId, string memory reason) external;
    
    /**
     * @dev Completes a transfer and confirms receipt
     * @param transferId Transfer identifier to complete
     * @param proofOfDelivery Cryptographic proof that file was received
     */
    function completeTransfer(bytes32 transferId, bytes32 proofOfDelivery) external;
    
    /**
     * @dev Raises a dispute for a transfer in progress
     * @param transferId Transfer identifier to dispute
     * @param reason Reason for the dispute
     */
    function disputeTransfer(bytes32 transferId, string memory reason) external;
    
    /**
     * @dev Resolves a disputed transfer (admin only)
     * @param transferId Transfer identifier to resolve
     * @param resolution Resolution decision
     */
    function resolveDispute(
        bytes32 transferId,
        TransferStructs.Resolution resolution
    ) external;
    
    /**
     * @dev Gets transfer details
     * @param transferId Transfer identifier
     * @return Transfer details
     */
    function getTransfer(bytes32 transferId)
        external
        view
        returns (TransferStructs.TransferView memory);
    
    /**
     * @dev Gets all transfers sent by a user
     * @param user Address of the user
     * @return Array of transfer identifiers
     */
    function getUserSentTransfers(address user)
        external
        view
        returns (bytes32[] memory);
    
    /**
     * @dev Gets all transfers received by a user
     * @param user Address of the user
     * @return Array of transfer identifiers
     */
    function getUserReceivedTransfers(address user)
        external
        view
        returns (bytes32[] memory);
}