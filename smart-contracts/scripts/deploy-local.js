const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("Starting local deployment...");
  
  // Get signers
  const [deployer, admin, operator] = await hre.ethers.getSigners();
  console.log(`Deploying contracts with account: ${deployer.address}`);
  console.log(`Admin account: ${admin.address}`);
  console.log(`Operator account: ${operator.address}`);
  
  // Deploy libraries first
  console.log("\nDeploying libraries...");
  
  const FileStructs = await hre.ethers.getContractFactory("FileStructs");
  const fileStructs = await FileStructs.deploy();
  await fileStructs.deployed();
  console.log(`FileStructs deployed to: ${fileStructs.address}`);
  
  const TransferStructs = await hre.ethers.getContractFactory("TransferStructs");
  const transferStructs = await TransferStructs.deploy();
  await transferStructs.deployed();
  console.log(`TransferStructs deployed to: ${transferStructs.address}`);
  
  const SecurityUtils = await hre.ethers.getContractFactory("SecurityUtils");
  const securityUtils = await SecurityUtils.deploy();
  await securityUtils.deployed();
  console.log(`SecurityUtils deployed to: ${securityUtils.address}`);
  
  // Deploy configuration contract
  console.log("\nDeploying SystemConfig...");
  const SystemConfig = await hre.ethers.getContractFactory("SystemConfig");
  const systemConfig = await SystemConfig.deploy(admin.address);
  await systemConfig.deployed();
  console.log(`SystemConfig deployed to: ${systemConfig.address}`);
  
  // Deploy access control contract
  console.log("\nDeploying AccessControlContract...");
  const AccessControlContract = await hre.ethers.getContractFactory("AccessControlContract");
  const accessControlContract = await AccessControlContract.deploy(admin.address);
  await accessControlContract.deployed();
  console.log(`AccessControlContract deployed to: ${accessControlContract.address}`);
  
  // Deploy AuditContract
  console.log("\nDeploying AuditContract...");
  const AuditContract = await hre.ethers.getContractFactory("AuditContract");
  const auditContract = await AuditContract.deploy(admin.address);
  await auditContract.deployed();
  console.log(`AuditContract deployed to: ${auditContract.address}`);
  
  // Deploy FileRegistry with links to libraries
  console.log("\nDeploying FileRegistry...");
  const maxFileSize = 100 * 1024 * 1024; // 100 MB
  const FileRegistryFactory = await hre.ethers.getContractFactory("FileRegistry", {
    libraries: {
      FileStructs: fileStructs.address
    }
  });
  const fileRegistry = await FileRegistryFactory.deploy(admin.address, maxFileSize);
  await fileRegistry.deployed();
  console.log(`FileRegistry deployed to: ${fileRegistry.address}`);
  
  // Deploy TransferContract with links to libraries
  console.log("\nDeploying TransferContract...");
  const TransferContractFactory = await hre.ethers.getContractFactory("TransferContract", {
    libraries: {
      FileStructs: fileStructs.address,
      TransferStructs: transferStructs.address
    }
  });
  const transferContract = await TransferContractFactory.deploy(
    fileRegistry.address,
    auditContract.address,
    admin.address
  );
  await transferContract.deployed();
  console.log(`TransferContract deployed to: ${transferContract.address}`);
  
  // Set up roles and permissions
  console.log("\nSetting up roles and permissions...");
  
  // Grant RECORDER_ROLE to TransferContract in AuditContract
  const RECORDER_ROLE = hre.ethers.utils.id("RECORDER_ROLE");
  const grantRecorderTx = await auditContract.connect(admin).grantRole(
    RECORDER_ROLE,
    transferContract.address
  );
  await grantRecorderTx.wait();
  console.log(`Granted RECORDER_ROLE to TransferContract in AuditContract`);
  
  // Grant OPERATOR_ROLE to operator in both contracts
  const OPERATOR_ROLE = hre.ethers.utils.id("OPERATOR_ROLE");
  await fileRegistry.connect(admin).grantRole(OPERATOR_ROLE, operator.address);
  await transferContract.connect(admin).grantRole(OPERATOR_ROLE, operator.address);
  console.log(`Granted OPERATOR_ROLE to ${operator.address}`);
  
  // Register contract addresses in SystemConfig
  await systemConfig.connect(admin).setContractAddress("FileRegistry", fileRegistry.address);
  await systemConfig.connect(admin).setContractAddress("TransferContract", transferContract.address);
  await systemConfig.connect(admin).setContractAddress("AuditContract", auditContract.address);
  await systemConfig.connect(admin).setContractAddress("AccessControl", accessControlContract.address);
  console.log("Registered contract addresses in SystemConfig");
  
  // Add contracts as trusted in AccessControlContract
  await accessControlContract.connect(admin).addTrustedContract(fileRegistry.address);
  await accessControlContract.connect(admin).addTrustedContract(transferContract.address);
  await accessControlContract.connect(admin).addTrustedContract(auditContract.address);
  console.log("Added contracts as trusted in AccessControlContract");
  
  // Save deployment information
  const deploymentInfo = {
    network: hre.network.name,
    timestamp: new Date().toISOString(),
    deployer: deployer.address,
    admin: admin.address,
    operator: operator.address,
    contracts: {
      FileStructs: fileStructs.address,
      TransferStructs: transferStructs.address,
      SecurityUtils: securityUtils.address,
      SystemConfig: systemConfig.address,
      AccessControlContract: accessControlContract.address,
      AuditContract: auditContract.address,
      FileRegistry: fileRegistry.address,
      TransferContract: transferContract.address
    }
  };
  
  const deploymentDir = path.join(__dirname, "../deployments");
  if (!fs.existsSync(deploymentDir)) {
    fs.mkdirSync(deploymentDir, { recursive: true });
  }
  
  fs.writeFileSync(
    path.join(deploymentDir, `${hre.network.name}-deployment.json`),
    JSON.stringify(deploymentInfo, null, 2)
  );
  console.log(`\nDeployment information saved to ${hre.network.name}-deployment.json`);
  
  console.log("\nDeployment completed successfully!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });