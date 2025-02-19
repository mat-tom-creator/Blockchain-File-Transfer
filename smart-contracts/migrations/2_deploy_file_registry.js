const FileRegistry = artifacts.require("FileRegistry");
const TransferContract = artifacts.require("TransferContract");
const AuditContract = artifacts.require("AuditContract");

// Libraries
const FileStructs = artifacts.require("FileStructs");
const TransferStructs = artifacts.require("TransferStructs");

module.exports = async function(deployer, network, accounts) {
  const admin = accounts[0];
  const operator = accounts[1];
  
  console.log(`Deploying contracts with admin: ${admin}`);
  console.log(`Network: ${network}`);
  
  // Deploy libraries first
  await deployer.deploy(FileStructs);
  await deployer.deploy(TransferStructs);
  
  // Link libraries to contracts
  await deployer.link(FileStructs, [FileRegistry, TransferContract]);
  await deployer.link(TransferStructs, TransferContract);
  
  // Deploy AuditContract first as it has no dependencies
  console.log("Deploying AuditContract...");
  await deployer.deploy(AuditContract, admin);
  const auditContract = await AuditContract.deployed();
  console.log(`AuditContract deployed at: ${auditContract.address}`);
  
  // Deploy FileRegistry with initial settings
  console.log("Deploying FileRegistry...");
  const maxFileSize = 1024 * 1024 * 100; // 100 MB
  await deployer.deploy(FileRegistry, admin, maxFileSize);
  const fileRegistry = await FileRegistry.deployed();
  console.log(`FileRegistry deployed at: ${fileRegistry.address}`);
  
  // Deploy TransferContract with references to other contracts
  console.log("Deploying TransferContract...");
  await deployer.deploy(
    TransferContract,
    fileRegistry.address,
    auditContract.address,
    admin
  );
  const transferContract = await TransferContract.deployed();
  console.log(`TransferContract deployed at: ${transferContract.address}`);
  
  // Set up roles and permissions
  if (network !== 'mainnet') {
    console.log("Setting up roles and permissions...");
    
    // Grant RECORDER_ROLE to TransferContract in AuditContract
    const RECORDER_ROLE = web3.utils.soliditySha3("RECORDER_ROLE");
    await auditContract.grantRole(RECORDER_ROLE, transferContract.address, { from: admin });
    console.log(`Granted RECORDER_ROLE to TransferContract in AuditContract`);
    
    // Grant OPERATOR_ROLE to specified account
    const OPERATOR_ROLE = web3.utils.soliditySha3("OPERATOR_ROLE");
    await fileRegistry.grantRole(OPERATOR_ROLE, operator, { from: admin });
    await transferContract.grantRole(OPERATOR_ROLE, operator, { from: admin });
    console.log(`Granted OPERATOR_ROLE to ${operator}`);
    
    // Additional setup for test environments
    if (network === 'development' || network === 'test') {
      // Create test files or setup test data if needed
      console.log("Development/test environment detected - setting up test data...");
      // Example: Pre-populate with test files could go here
    }
  }
  
  console.log("Deployment completed successfully!");
};