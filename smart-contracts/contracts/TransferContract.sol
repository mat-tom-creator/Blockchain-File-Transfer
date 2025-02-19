// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/ITransferContract.sol";
import "./interfaces/IFileRegistry.sol";
import "./interfaces/IAuditContract.sol";
import "./libraries/TransferStructs.sol";
import "./libraries/FileStructs.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title TransferContract
 * @dev Manages file transfers between users
 */
contract TransferContract is ITransferContract, AccessControl, ReentrancyGuard, Pausable {
    using Counters for Counters.Counter;
    
    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    // State variables
    IFileRegistry private _fileRegistry;
    IAuditContract private _auditContract;
    
    mapping(bytes32 => TransferStructs.Transfer) private _transfers;
    mapping(address => bytes32[]) private _userSentTransfers;
    mapping(address => bytes32[]) private _userReceivedTransfers;
    
    Counters.Counter private _transferIdCounter;
    uint256 public transferExpirationTime; // In seconds
    
    // Events
    event TransferInitiated(
        bytes32 indexed transferId, 
        bytes32 indexed fileId, 
        address indexed sender, 
        address recipient
    );
    event TransferCancelled(bytes32 indexed transferId);
    event TransferAccepted(bytes32 indexed transferId);
    event TransferRejected(bytes32 indexed transferId, string reason);
    event TransferCompleted(bytes32 indexed transferId, bytes32 proofOfDelivery);
    event TransferDisputed(bytes32 indexed transferId, string reason);
    event TransferResolved(bytes32 indexed transferId, TransferStructs.Resolution resolution);
    
    /**
     * @dev Constructor
     * @param fileRegistryAddress Address of the FileRegistry contract
     * @param auditContractAddress Address of the AuditContract
     * @param initialAdmin Address of the initial admin
     */
    constructor(
        address fileRegistryAddress,
        address auditContractAddress,
        address initialAdmin
    ) {
        require(fileRegistryAddress != address(0), "Invalid FileRegistry address");
        
        _fileRegistry = IFileRegistry(fileRegistryAddress);
        
        if (auditContractAddress != address(0)) {
            _auditContract = IAuditContract(auditContractAddress);
        }
        
        _setupRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _setupRole(ADMIN_ROLE, initialAdmin);
        
        transferExpirationTime = 7 days; // Default 7 days
    }
    
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
    ) 
        external 
        whenNotPaused
        nonReentrant
        returns (bytes32 transferId)
    {
        require(recipient != address(0), "Invalid recipient");
        require(recipient != msg.sender, "Cannot transfer to self");
        
        // Verify sender has access to the file
        require(
            _fileRegistry.checkAccess(fileId, msg.sender, FileStructs.AccessLevel.READ),
            "No access to file"
        );
        
        // Generate transfer ID
        _transferIdCounter.increment();
        transferId = keccak256(abi.encodePacked(
            fileId,
            msg.sender,
            recipient,
            _transferIdCounter.current(),
            block.timestamp
        ));
        
        // Calculate deadline
        uint256 deadline = transferDeadline == 0 
            ? block.timestamp + transferExpirationTime 
            : transferDeadline;
        
        require(deadline > block.timestamp, "Deadline must be in the future");
        
        // Create transfer record
        TransferStructs.Transfer memory newTransfer = TransferStructs.Transfer({
            transferId: transferId,
            fileId: fileId,
            sender: msg.sender,
            recipient: recipient,
            message: message,
            initiatedAt: block.timestamp,
            deadline: deadline,
            completedAt: 0,
            status: TransferStructs.TransferStatus.INITIATED,
            accessLevel: accessLevel,
            proofOfDelivery: bytes32(0),
            disputeReason: "",
            resolution: TransferStructs.Resolution.NONE
        });
        
        _transfers[transferId] = newTransfer;
        _userSentTransfers[msg.sender].push(transferId);
        _userReceivedTransfers[recipient].push(transferId);
        
        // Log to audit trail if available
        if (address(_auditContract) != address(0)) {
            _auditContract.recordAction(
                fileId,
                string(abi.encodePacked("Transfer initiated to ", _addressToString(recipient)))
            );
        }
        
        emit TransferInitiated(transferId, fileId, msg.sender, recipient);
        return transferId;
    }
    
    /**
     * @dev Cancels a pending transfer (sender only)
     * @param transferId Transfer identifier to cancel
     */
    function cancelTransfer(bytes32 transferId)
        external
        whenNotPaused
        nonReentrant
    {
        TransferStructs.Transfer storage transfer = _transfers[transferId];
        
        require(transfer.transferId == transferId, "Transfer does not exist");
        require(transfer.sender == msg.sender, "Only sender can cancel");
        require(
            transfer.status == TransferStructs.TransferStatus.INITIATED,
            "Transfer cannot be cancelled"
        );
        
        transfer.status = TransferStructs.TransferStatus.CANCELLED;
        
        // Log to audit trail if available
        if (address(_auditContract) != address(0)) {
            _auditContract.recordAction(
                transfer.fileId,
                "Transfer cancelled by sender"
            );
        }
        
        emit TransferCancelled(transferId);
    }
    
    /**
     * @dev Accepts a pending transfer (recipient only)
     * @param transferId Transfer identifier to accept
     */
    function acceptTransfer(bytes32 transferId)
        external
        whenNotPaused
        nonReentrant
    {
        TransferStructs.Transfer storage transfer = _transfers[transferId];
        
        require(transfer.transferId == transferId, "Transfer does not exist");
        require(transfer.recipient == msg.sender, "Only recipient can accept");
        require(
            transfer.status == TransferStructs.TransferStatus.INITIATED,
            "Transfer cannot be accepted"
        );
        require(block.timestamp <= transfer.deadline, "Transfer expired");
        
        transfer.status = TransferStructs.TransferStatus.IN_PROGRESS;
        
        // Log to audit trail if available
        if (address(_auditContract) != address(0)) {
            _auditContract.recordAction(
                transfer.fileId,
                "Transfer accepted by recipient"
            );
        }
        
        emit TransferAccepted(transferId);
    }
    
    /**
     * @dev Rejects a pending transfer (recipient only)
     * @param transferId Transfer identifier to reject
     * @param reason Reason for rejection
     */
    function rejectTransfer(
        bytes32 transferId,
        string memory reason
    )
        external
        whenNotPaused
        nonReentrant
    {
        TransferStructs.Transfer storage transfer = _transfers[transferId];
        
        require(transfer.transferId == transferId, "Transfer does not exist");
        require(transfer.recipient == msg.sender, "Only recipient can reject");
        require(
            transfer.status == TransferStructs.TransferStatus.INITIATED,
            "Transfer cannot be rejected"
        );
        
        transfer.status = TransferStructs.TransferStatus.REJECTED;
        
        // Log to audit trail if available
        if (address(_auditContract) != address(0)) {
            _auditContract.recordAction(
                transfer.fileId,
                string(abi.encodePacked("Transfer rejected by recipient: ", reason))
            );
        }
        
        emit TransferRejected(transferId, reason);
    }
    
    /**
     * @dev Completes a transfer and confirms receipt
     * @param transferId Transfer identifier to complete
     * @param proofOfDelivery Cryptographic proof that file was received
     */
    function completeTransfer(
        bytes32 transferId,
        bytes32 proofOfDelivery
    )
        external
        whenNotPaused
        nonReentrant
    {
        require(proofOfDelivery != bytes32(0), "Invalid proof of delivery");
        
        TransferStructs.Transfer storage transfer = _transfers[transferId];
        
        require(transfer.transferId == transferId, "Transfer does not exist");
        require(transfer.recipient == msg.sender, "Only recipient can complete");
        require(
            transfer.status == TransferStructs.TransferStatus.IN_PROGRESS,
            "Transfer not in progress"
        );
        
        transfer.status = TransferStructs.TransferStatus.COMPLETED;
        transfer.completedAt = block.timestamp;
        transfer.proofOfDelivery = proofOfDelivery;
        
        // Grant specified access to the recipient
        try _fileRegistry.grantAccess(
            transfer.fileId,
            transfer.recipient,
            transfer.accessLevel,
            0  // No expiration
        ) {
            // Access granted successfully
        } catch {
            // Continue even if access granting fails
            // The transfer itself is still valid
        }
        
        // Log to audit trail if available
        if (address(_auditContract) != address(0)) {
            _auditContract.recordAction(
                transfer.fileId,
                "Transfer completed, receipt confirmed"
            );
        }
        
        emit TransferCompleted(transferId, proofOfDelivery);
    }
    
    /**
     * @dev Raises a dispute for a transfer in progress
     * @param transferId Transfer identifier to dispute
     * @param reason Reason for the dispute
     */
    function disputeTransfer(
        bytes32 transferId,
        string memory reason
    )
        external
        whenNotPaused
        nonReentrant
    {
        TransferStructs.Transfer storage transfer = _transfers[transferId];
        
        require(transfer.transferId == transferId, "Transfer does not exist");
        require(
            transfer.sender == msg.sender || transfer.recipient == msg.sender,
            "Only sender or recipient can dispute"
        );
        require(
            transfer.status == TransferStructs.TransferStatus.IN_PROGRESS ||
            transfer.status == TransferStructs.TransferStatus.COMPLETED,
            "Transfer cannot be disputed"
        );
        
        transfer.status = TransferStructs.TransferStatus.DISPUTED;
        transfer.disputeReason = reason;
        
        // Log to audit trail if available
        if (address(_auditContract) != address(0)) {
            string memory action = msg.sender == transfer.sender 
                ? "Transfer disputed by sender: " 
                : "Transfer disputed by recipient: ";
            
            _auditContract.recordAction(
                transfer.fileId,
                string(abi.encodePacked(action, reason))
            );
        }
        
        emit TransferDisputed(transferId, reason);
    }
    
    /**
     * @dev Resolves a disputed transfer (admin only)
     * @param transferId Transfer identifier to resolve
     * @param resolution Resolution decision
     */
    function resolveDispute(
        bytes32 transferId,
        TransferStructs.Resolution resolution
    )
        external
        whenNotPaused
        nonReentrant
        onlyRole(ADMIN_ROLE)
    {
        TransferStructs.Transfer storage transfer = _transfers[transferId];
        
        require(transfer.transferId == transferId, "Transfer does not exist");
        require(
            transfer.status == TransferStructs.TransferStatus.DISPUTED,
            "Transfer not disputed"
        );
        require(
            resolution != TransferStructs.Resolution.NONE,
            "Invalid resolution"
        );
        
        transfer.resolution = resolution;
        
        if (resolution == TransferStructs.Resolution.COMPLETED) {
            transfer.status = TransferStructs.TransferStatus.COMPLETED;
            
            // Grant specified access to the recipient if resolved as completed
            try _fileRegistry.grantAccess(
                transfer.fileId,
                transfer.recipient,
                transfer.accessLevel,
                0  // No expiration
            ) {
                // Access granted successfully
            } catch {
                // Continue even if access granting fails
            }
            
        } else if (resolution == TransferStructs.Resolution.CANCELLED) {
            transfer.status = TransferStructs.TransferStatus.CANCELLED;
        }
        
        // Log to audit trail if available
        if (address(_auditContract) != address(0)) {
            string memory resolutionStr = resolution == TransferStructs.Resolution.COMPLETED
                ? "completed"
                : "cancelled";
                
            _auditContract.recordAction(
                transfer.fileId,
                string(abi.encodePacked("Disputed transfer resolved as ", resolutionStr, " by admin"))
            );
        }
        
        emit TransferResolved(transferId, resolution);
    }
    
    /**
     * @dev Gets transfer details
     * @param transferId Transfer identifier
     * @return Transfer details
     */
    function getTransfer(bytes32 transferId)
        external
        view
        returns (TransferStructs.TransferView memory)
    {
        TransferStructs.Transfer storage transfer = _transfers[transferId];
        require(transfer.transferId == transferId, "Transfer does not exist");
        
        // Only sender, recipient, or admin can view transfer details
        require(
            transfer.sender == msg.sender ||
            transfer.recipient == msg.sender ||
            hasRole(ADMIN_ROLE, msg.sender) ||
            hasRole(OPERATOR_ROLE, msg.sender),
            "Not authorized"
        );
        
        return TransferStructs.TransferView({
            transferId: transfer.transferId,
            fileId: transfer.fileId,
            sender: transfer.sender,
            recipient: transfer.recipient,
            message: transfer.message,
            initiatedAt: transfer.initiatedAt,
            deadline: transfer.deadline,
            completedAt: transfer.completedAt,
            status: transfer.status,
            accessLevel: transfer.accessLevel,
            proofOfDelivery: transfer.proofOfDelivery,
            disputeReason: transfer.disputeReason,
            resolution: transfer.resolution
        });
    }
    
    /**
     * @dev Gets all transfers sent by a user
     * @param user Address of the user
     * @return Array of transfer identifiers
     */
    function getUserSentTransfers(address user)
        external
        view
        returns (bytes32[] memory)
    {
        require(
            user == msg.sender || 
            hasRole(ADMIN_ROLE, msg.sender) || 
            hasRole(OPERATOR_ROLE, msg.sender),
            "Not authorized"
        );
        
        return _userSentTransfers[user];
    }
    
    /**
     * @dev Gets all transfers received by a user
     * @param user Address of the user
     * @return Array of transfer identifiers
     */
    function getUserReceivedTransfers(address user)
        external
        view
        returns (bytes32[] memory)
    {
        require(
            user == msg.sender || 
            hasRole(ADMIN_ROLE, msg.sender) || 
            hasRole(OPERATOR_ROLE, msg.sender),
            "Not authorized"
        );
        
        return _userReceivedTransfers[user];
    }
    
    /**
     * @dev Sets the file registry contract address
     * @param newFileRegistry Address of the new file registry contract
     */
    function setFileRegistry(address newFileRegistry)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(newFileRegistry != address(0), "Invalid FileRegistry address");
        _fileRegistry = IFileRegistry(newFileRegistry);
    }
    
    /**
     * @dev Sets the audit contract address
     * @param newAuditContract Address of the new audit contract
     */
    function setAuditContract(address newAuditContract)
        external
        onlyRole(ADMIN_ROLE)
    {
        _auditContract = IAuditContract(newAuditContract);
    }
    
    /**
     * @dev Sets the transfer expiration time
     * @param newExpirationTime New expiration time in seconds
     */
    function setTransferExpirationTime(uint256 newExpirationTime)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(newExpirationTime > 0, "Expiration time must be positive");
        transferExpirationTime = newExpirationTime;
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
    
    /**
     * @dev Utility function to convert address to string
     * @param addr Address to convert
     * @return String representation of the address
     */
    function _addressToString(address addr) private pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(addr)));
        bytes memory alphabet = "0123456789abcdef";
        
        bytes memory str = new bytes(42);
        str[0] = '0';
        str[1] = 'x';
        
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        
        return string(str);
    }
}