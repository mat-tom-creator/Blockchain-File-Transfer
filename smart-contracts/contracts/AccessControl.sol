// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./interfaces/IFileRegistry.sol";
import "./libraries/FileStructs.sol";

/**
 * @title AccessControlContract
 * @dev Manages access control and permissions for the file transfer system
 */
contract AccessControlContract is AccessControl, Pausable {
    using Counters for Counters.Counter;

    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant TRANSFER_MANAGER_ROLE = keccak256("TRANSFER_MANAGER_ROLE");
    bytes32 public constant AUDITOR_ROLE = keccak256("AUDITOR_ROLE");

    // Governance parameters
    uint256 public minAdminThreshold;
    mapping(address => bool) public trustedContracts;
    
    // Role counters
    mapping(bytes32 => Counters.Counter) private _roleCounters;
    
    // Events
    event RoleThresholdUpdated(bytes32 indexed role, uint256 threshold);
    event TrustedContractAdded(address indexed contractAddress);
    event TrustedContractRemoved(address indexed contractAddress);
    event MultiRoleGranted(address indexed account, bytes32[] roles);
    
    /**
     * @dev Constructor
     * @param initialAdmin Address of the initial admin
     */
    constructor(address initialAdmin) {
        require(initialAdmin != address(0), "Invalid admin address");
        
        _setupRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _setupRole(ADMIN_ROLE, initialAdmin);
        
        // Set initial threshold to 1
        minAdminThreshold = 1;
        _roleCounters[ADMIN_ROLE].increment();
    }
    
    /**
     * @dev Modifier to restrict access to trusted contracts
     */
    modifier onlyTrustedContract() {
        require(
            trustedContracts[msg.sender],
            "Caller is not a trusted contract"
        );
        _;
    }
    
    /**
     * @dev Adds a contract to the trusted contracts list
     * @param contractAddress Address of the contract to add
     */
    function addTrustedContract(address contractAddress)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(contractAddress != address(0), "Invalid contract address");
        require(!trustedContracts[contractAddress], "Contract already trusted");
        
        trustedContracts[contractAddress] = true;
        emit TrustedContractAdded(contractAddress);
    }
    
    /**
     * @dev Removes a contract from the trusted contracts list
     * @param contractAddress Address of the contract to remove
     */
    function removeTrustedContract(address contractAddress)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(trustedContracts[contractAddress], "Contract not trusted");
        
        trustedContracts[contractAddress] = false;
        emit TrustedContractRemoved(contractAddress);
    }
    
    /**
     * @dev Sets minimum threshold for admin operations
     * @param newThreshold New threshold value
     */
    function setMinAdminThreshold(uint256 newThreshold)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(newThreshold > 0, "Threshold must be positive");
        uint256 adminCount = _roleCounters[ADMIN_ROLE].current();
        require(newThreshold <= adminCount, "Threshold exceeds admin count");
        
        minAdminThreshold = newThreshold;
        emit RoleThresholdUpdated(ADMIN_ROLE, newThreshold);
    }
    
    /**
     * @dev Grants multiple roles to an account
     * @param account Address to grant roles to
     * @param roles Array of role identifiers
     */
    function grantMultipleRoles(address account, bytes32[] memory roles)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(account != address(0), "Invalid account address");
        
        for (uint256 i = 0; i < roles.length; i++) {
            grantRole(roles[i], account);
            _roleCounters[roles[i]].increment();
        }
        
        emit MultiRoleGranted(account, roles);
    }
    
    /**
     * @dev Revokes a role from an account with protection for last admin
     * @param role Role to revoke
     * @param account Address to revoke role from
     */
    function revokeRoleSafely(bytes32 role, address account)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(account != address(0), "Invalid account address");
        
        if (role == ADMIN_ROLE) {
            uint256 adminCount = _roleCounters[ADMIN_ROLE].current();
            require(adminCount > minAdminThreshold, "Cannot reduce admins below threshold");
            _roleCounters[ADMIN_ROLE].decrement();
        } else {
            _roleCounters[role].decrement();
        }
        
        revokeRole(role, account);
    }
    
    /**
     * @dev Checks if account has specific permissions for a file
     * @param fileRegistry Address of file registry contract
     * @param fileId File identifier
     * @param account Account to check
     * @param requiredLevel Required access level
     * @return hasAccess Whether account has required access
     */
    function checkFilePermission(
        address fileRegistry,
        bytes32 fileId,
        address account,
        FileStructs.AccessLevel requiredLevel
    )
        external
        view
        returns (bool hasAccess)
    {
        // Admins have access to everything
        if (hasRole(ADMIN_ROLE, account)) {
            return true;
        }
        
        // Check file-specific permissions
        return IFileRegistry(fileRegistry).checkAccess(
            fileId,
            account,
            requiredLevel
        );
    }
    
    /**
     * @dev Gets the count of accounts with a specific role
     * @param role Role identifier
     * @return count Number of accounts with role
     */
    function getRoleCount(bytes32 role)
        external
        view
        returns (uint256 count)
    {
        return _roleCounters[role].current();
    }
    
    /**
     * @dev Pauses critical contract operations
     */
    function pause()
        external
        onlyRole(ADMIN_ROLE)
    {
        _pause();
    }
    
    /**
     * @dev Resumes critical contract operations
     */
    function unpause()
        external
        onlyRole(ADMIN_ROLE)
    {
        _unpause();
    }
}