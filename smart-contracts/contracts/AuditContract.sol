// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/IAuditContract.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title AuditContract
 * @dev Maintains an immutable audit trail for file operations
 */
contract AuditContract is IAuditContract, AccessControl, ReentrancyGuard, Pausable {
    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant RECORDER_ROLE = keccak256("RECORDER_ROLE");
    
    // Structs
    struct AuditRecord {
        bytes32 recordId;
        bytes32 fileId;
        address actor;
        string action;
        uint256 timestamp;
        bytes32 previousRecordHash;
    }
    
    // State variables
    mapping(bytes32 => AuditRecord[]) private _fileAudits;
    mapping(bytes32 => bytes32) private _lastRecordHash;
    mapping(bytes32 => uint256) private _recordCounts;
    
    // Events
    event AuditRecorded(
        bytes32 indexed recordId,
        bytes32 indexed fileId,
        address indexed actor,
        string action,
        uint256 timestamp
    );
    
    /**
     * @dev Constructor
     * @param initialAdmin Address of the initial admin
     */
    constructor(address initialAdmin) {
        _setupRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _setupRole(ADMIN_ROLE, initialAdmin);
        _setupRole(RECORDER_ROLE, initialAdmin);
    }
    
    /**
     * @dev Records an action in the audit trail
     * @param fileId File identifier
     * @param action Description of the action
     * @return recordId Unique identifier for the audit record
     */
    function recordAction(
        bytes32 fileId,
        string memory action
    ) 
        external 
        override
        whenNotPaused
        nonReentrant
        returns (bytes32 recordId)
    {
        require(
            hasRole(RECORDER_ROLE, msg.sender),
            "Must have recorder role"
        );
        require(bytes(action).length > 0, "Action description required");
        
        bytes32 previousHash = _lastRecordHash[fileId];
        
        // Generate a unique record ID
        recordId = keccak256(abi.encodePacked(
            fileId,
            msg.sender,
            action,
            block.timestamp,
            previousHash
        ));
        
        // Create and store audit record
        AuditRecord memory newRecord = AuditRecord({
            recordId: recordId,
            fileId: fileId,
            actor: msg.sender,
            action: action,
            timestamp: block.timestamp,
            previousRecordHash: previousHash
        });
        
        _fileAudits[fileId].push(newRecord);
        _lastRecordHash[fileId] = recordId;
        _recordCounts[fileId]++;
        
        emit AuditRecorded(recordId, fileId, msg.sender, action, block.timestamp);
        return recordId;
    }
    
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
    ) 
        external 
        view 
        returns (AuditRecord[] memory records, uint256 total)
    {
        total = _recordCounts[fileId];
        
        if (total == 0 || offset >= total) {
            return (new AuditRecord[](0), total);
        }
        
        // Calculate actual limit based on available records
        uint256 actualLimit = (limit == 0 || offset + limit > total) 
            ? total - offset 
            : limit;
        
        records = new AuditRecord[](actualLimit);
        
        for (uint256 i = 0; i < actualLimit; i++) {
            records[i] = _fileAudits[fileId][offset + i];
        }
        
        return (records, total);
    }
    
    /**
     * @dev Gets a specific audit record
     * @param fileId File identifier
     * @param recordId Record identifier
     * @return record The audit record
     */
    function getAuditRecord(
        bytes32 fileId,
        bytes32 recordId
    ) 
        external 
        view 
        returns (AuditRecord memory record)
    {
        AuditRecord[] storage records = _fileAudits[fileId];
        
        for (uint256 i = 0; i < records.length; i++) {
            if (records[i].recordId == recordId) {
                return records[i];
            }
        }
        
        revert("Record not found");
    }
    
    /**
     * @dev Verifies the integrity of the audit trail
     * @param fileId File identifier
     * @return isValid True if the audit trail is valid
     */
    function verifyAuditTrail(bytes32 fileId) 
        external 
        view 
        returns (bool isValid)
    {
        AuditRecord[] storage records = _fileAudits[fileId];
        
        if (records.length == 0) {
            return true; // Empty trail is valid
        }
        
        bytes32 expectedPreviousHash = bytes32(0);
        
        for (uint256 i = 0; i < records.length; i++) {
            // Verify previous hash
            if (records[i].previousRecordHash != expectedPreviousHash) {
                return false;
            }
            
            // Calculate this record's hash for the next iteration
            expectedPreviousHash = records[i].recordId;
        }
        
        // Verify the last record matches our stored last hash
        return _lastRecordHash[fileId] == expectedPreviousHash;
    }
    
    /**
     * @dev Gets the last record hash for a file
     * @param fileId File identifier
     * @return lastHash Hash of the last audit record
     */
    function getLastRecordHash(bytes32 fileId) 
        external 
        view 
        returns (bytes32 lastHash)
    {
        return _lastRecordHash[fileId];
    }
    
    /**
     * @dev Gets the count of audit records for a file
     * @param fileId File identifier
     * @return count Number of audit records
     */
    function getRecordCount(bytes32 fileId) 
        external 
        view 
        returns (uint256 count)
    {
        return _recordCounts[fileId];
    }
    
    /**
     * @dev Grants the recorder role to an address
     * @param account Address to grant role to
     */
    function addRecorder(address account) 
        external 
        onlyRole(ADMIN_ROLE)
    {
        grantRole(RECORDER_ROLE, account);
    }
    
    /**
     * @dev Revokes the recorder role from an address
     * @param account Address to revoke role from
     */
    function removeRecorder(address account) 
        external 
        onlyRole(ADMIN_ROLE)
    {
        revokeRole(RECORDER_ROLE, account);
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