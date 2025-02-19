// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title SystemConfig
 * @dev Manages global configuration for the file transfer system
 */
contract SystemConfig is AccessControl, Pausable {
    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant CONFIG_MANAGER_ROLE = keccak256("CONFIG_MANAGER_ROLE");

    // Storage settings
    uint256 public maxFileSize;             // Maximum file size in bytes
    uint256 public maxStoragePerUser;       // Maximum storage per user in bytes
    uint256 public minChunkSize;            // Minimum chunk size for file splitting
    uint256 public maxChunks;               // Maximum number of chunks per file
    
    // Transfer settings
    uint256 public defaultTransferTimeout;  // Default timeout for transfers in seconds
    uint256 public maxTransferTimeout;      // Maximum allowed timeout for transfers
    uint256 public defaultDisputeTimeout;   // Default timeout for disputes
    
    // Security settings
    bool public enforceEncryption;          // Whether encryption is mandatory
    string public defaultEncryptionScheme;  // Default encryption scheme
    uint256 public minKeyLength;            // Minimum encryption key length
    
    // Contract addresses
    mapping(string => address) public contractAddresses;
    
    // Events
    event StorageSettingUpdated(string setting, uint256 value);
    event TransferSettingUpdated(string setting, uint256 value);
    event SecuritySettingUpdated(string setting);
    event ContractAddressUpdated(string name, address addr);
    
    /**
     * @dev Constructor
     * @param initialAdmin Address of the initial admin
     */
    constructor(address initialAdmin) {
        require(initialAdmin != address(0), "Invalid admin address");
        
        _setupRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _setupRole(ADMIN_ROLE, initialAdmin);
        _setupRole(CONFIG_MANAGER_ROLE, initialAdmin);
        
        // Initialize default settings
        maxFileSize = 1073741824;         // 1 GB
        maxStoragePerUser = 10737418240;  // 10 GB
        minChunkSize = 1048576;           // 1 MB
        maxChunks = 1000;
        
        defaultTransferTimeout = 7 days;
        maxTransferTimeout = 30 days;
        defaultDisputeTimeout = 14 days;
        
        enforceEncryption = true;
        defaultEncryptionScheme = "AES-256-GCM";
        minKeyLength = 256;
    }
    
    /**
     * @dev Sets storage-related settings
     * @param setting Setting name
     * @param value New value
     */
    function setStorageSetting(string memory setting, uint256 value)
        external
        whenNotPaused
        onlyRole(CONFIG_MANAGER_ROLE)
    {
        bytes32 settingHash = keccak256(bytes(setting));
        
        if (settingHash == keccak256(bytes("maxFileSize"))) {
            require(value > 0, "Invalid file size");
            maxFileSize = value;
        }
        else if (settingHash == keccak256(bytes("maxStoragePerUser"))) {
            require(value >= maxFileSize, "Must be >= maxFileSize");
            maxStoragePerUser = value;
        }
        else if (settingHash == keccak256(bytes("minChunkSize"))) {
            require(value > 0, "Invalid chunk size");
            minChunkSize = value;
        }
        else if (settingHash == keccak256(bytes("maxChunks"))) {
            require(value > 0, "Invalid max chunks");
            maxChunks = value;
        }
        else {
            revert("Unknown storage setting");
        }
        
        emit StorageSettingUpdated(setting, value);
    }
    
    /**
     * @dev Sets transfer-related settings
     * @param setting Setting name
     * @param value New value
     */
    function setTransferSetting(string memory setting, uint256 value)
        external
        whenNotPaused
        onlyRole(CONFIG_MANAGER_ROLE)
    {
        bytes32 settingHash = keccak256(bytes(setting));
        
        if (settingHash == keccak256(bytes("defaultTransferTimeout"))) {
            require(value > 0 && value <= maxTransferTimeout, "Invalid timeout");
            defaultTransferTimeout = value;
        }
        else if (settingHash == keccak256(bytes("maxTransferTimeout"))) {
            require(value >= defaultTransferTimeout, "Must be >= defaultTimeout");
            maxTransferTimeout = value;
        }
        else if (settingHash == keccak256(bytes("defaultDisputeTimeout"))) {
            require(value > 0, "Invalid dispute timeout");
            defaultDisputeTimeout = value;
        }
        else {
            revert("Unknown transfer setting");
        }
        
        emit TransferSettingUpdated(setting, value);
    }
    
    /**
     * @dev Sets security-related settings
     * @param enforceEncryptionFlag Whether to enforce encryption
     * @param encryptionScheme Default encryption scheme
     * @param keyLength Minimum key length
     */
    function setSecuritySettings(
        bool enforceEncryptionFlag,
        string memory encryptionScheme,
        uint256 keyLength
    )
        external
        whenNotPaused
        onlyRole(CONFIG_MANAGER_ROLE)
    {
        require(bytes(encryptionScheme).length > 0, "Invalid encryption scheme");
        require(keyLength >= 128, "Key length too short");
        
        enforceEncryption = enforceEncryptionFlag;
        defaultEncryptionScheme = encryptionScheme;
        minKeyLength = keyLength;
        
        emit SecuritySettingUpdated("security_settings_updated");
    }
    
    /**
     * @dev Updates a contract address
     * @param name Contract name
     * @param addr Contract address
     */
    function setContractAddress(string memory name, address addr)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(bytes(name).length > 0, "Name cannot be empty");
        require(addr != address(0), "Invalid address");
        
        contractAddresses[name] = addr;
        emit ContractAddressUpdated(name, addr);
    }
    
    /**
     * @dev Gets a contract address by name
     * @param name Contract name
     * @return Contract address
     */
    function getContractAddress(string memory name)
        external
        view
        returns (address)
    {
        address addr = contractAddresses[name];
        require(addr != address(0), "Contract not registered");
        return addr;
    }
    
    /**
     * @dev Checks if a file size is allowed
     * @param size File size to check
     * @return Whether size is allowed
     */
    function isFileSizeAllowed(uint256 size)
        external
        view
        returns (bool)
    {
        return size > 0 && size <= maxFileSize;
    }
    
    /**
     * @dev Gets all storage settings
     * @return Settings as a struct
     */
    function getStorageSettings()
        external
        view
        returns (
            uint256 _maxFileSize,
            uint256 _maxStoragePerUser,
            uint256 _minChunkSize,
            uint256 _maxChunks
        )
    {
        return (
            maxFileSize,
            maxStoragePerUser,
            minChunkSize,
            maxChunks
        );
    }
    
    /**
     * @dev Gets all transfer settings
     * @return Settings as a struct
     */
    function getTransferSettings()
        external
        view
        returns (
            uint256 _defaultTransferTimeout,
            uint256 _maxTransferTimeout,
            uint256 _defaultDisputeTimeout
        )
    {
        return (
            defaultTransferTimeout,
            maxTransferTimeout,
            defaultDisputeTimeout
        );
    }
    
    /**
     * @dev Gets all security settings
     * @return Settings as a struct
     */
    function getSecuritySettings()
        external
        view
        returns (
            bool _enforceEncryption,
            string memory _defaultEncryptionScheme,
            uint256 _minKeyLength
        )
    {
        return (
            enforceEncryption,
            defaultEncryptionScheme,
            minKeyLength
        );
    }
    
    /**
     * @dev Pauses configuration updates
     */
    function pause()
        external
        onlyRole(ADMIN_ROLE)
    {
        _pause();
    }
    
    /**
     * @dev Resumes configuration updates
     */
    function unpause()
        external
        onlyRole(ADMIN_ROLE)
    {
        _unpause();
    }
}