// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title IAuditContract
 * @dev Interface for the AuditContract
 */
interface IAuditContract {
    /**
     * @dev Records an action in the audit trail
     * @param fileId File identifier
     * @param action Description of the action
     * @return recordId Unique identifier for the audit record
     */
    function recordAction(
        bytes32 fileId,
        string memory action
    ) external returns (bytes32 recordId);
    
    /**
     * @dev Gets the audit trail for a file
     * @param fileId File identifier
     * @param offset Starting index for pagination
     * @param limit Maximum number of records to return
     * @return records Array of audit records
     * @return total Total number of records
     */
    function getAuditTrail(
        bytes32 fileId,
        uint256 offset,
        uint256 limit
    ) external view returns (
        AuditContract.AuditRecord[] memory records,
        uint256 total
    );
    
    /**
     * @dev Gets a specific audit record
     * @param fileId File identifier
     * @param recordId Record identifier
     * @return record The audit record
     */
    function getAuditRecord(
        bytes32 fileId,
        bytes32 recordId
    ) external view returns (AuditContract.AuditRecord memory record);
    
    /**
     * @dev Verifies the integrity of the audit trail
     * @param fileId File identifier
     * @return isValid True if the audit trail is valid
     */
    function verifyAuditTrail(bytes32 fileId) 
        external 
        view 
        returns (bool isValid);
    
    /**
     * @dev Gets the last record hash for a file
     * @param fileId File identifier
     * @return lastHash Hash of the last audit record
     */
    function getLastRecordHash(bytes32 fileId) 
        external 
        view 
        returns (bytes32 lastHash);
    
    /**
     * @dev Gets the count of audit records for a file
     * @param fileId File identifier
     * @return count Number of audit records
     */
    function getRecordCount(bytes32 fileId) 
        external 
        view 
        returns (uint256 count);
}

// Define interface to the audit record struct since it's used in function returns
interface AuditContract {
    struct AuditRecord {
        bytes32 recordId;
        bytes32 fileId;
        address actor;
        string action;
        uint256 timestamp;
        bytes32 previousRecordHash;
    }
}