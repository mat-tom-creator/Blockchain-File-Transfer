const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log(`Verifying contracts on ${hre.network.name}...`);
  
  // Load deployment info
  const deploymentPath = path.join(
    __dirname,
    "../deployments",
    `${hre.network.name}-deployment.json`
  );
  
  if (!fs.existsSync(deploymentPath)) {
    console.error(`Deployment file not found for network ${hre.network.name}`);
    process.exit(1);
  }
  
  const deploymentInfo = JSON.parse(fs.readFileSync(deploymentPath, "utf8"));
  const contracts = deploymentInfo.contracts;
  
  // Verify libraries first
  console.log("\nVerifying libraries...");
  
  try {
    await hre.run("verify:verify", {
      address: contracts.FileStructs,
      contract: "contracts/libraries/FileStructs.sol:FileStructs"
    });
    console.log("FileStructs verified successfully");
  } catch (error) {
    console.error("Error verifying FileStructs:", error.message);
  }
  
  try {
    await hre.run("verify:verify", {
      address: contracts.TransferStructs,
      contract: "contracts/libraries/TransferStructs.sol:TransferStructs"
    });
    console.log("TransferStructs verified successfully");
  } catch (error) {
    console.error("Error verifying TransferStructs:", error.message);
  }
  
  try {
    await hre.run("verify:verify", {
      address: contracts.SecurityUtils,
      contract: "contracts/libraries/SecurityUtils.sol:SecurityUtils"
    });
    console.log("SecurityUtils verified successfully");
  } catch (error) {
    console.error("Error verifying SecurityUtils:", error.message);
  }
  
  // Verify config contracts
  console.log("\nVerifying configuration contracts...");
  
  try {
    await hre.run("verify:verify", {
      address: contracts.SystemConfig,
      constructorArguments: [deploymentInfo.admin]
    });
    console.log("SystemConfig verified successfully");
  } catch (error) {
    console.error("Error verifying SystemConfig:", error.message);
  }
  
  try {
    await hre.run("verify:verify", {
      address: contracts.AccessControlContract,
      constructorArguments: [deploymentInfo.admin]
    });
    console.log("AccessControlContract verified successfully");
  } catch (error) {
    console.error("Error verifying AccessControlContract:", error.message);
  }
  
  // Verify core contracts
  console.log("\nVerifying core contracts...");
  
  try {
    await hre.run("verify:verify", {
      address: contracts.AuditContract,
      constructorArguments: [deploymentInfo.admin]
    });
    console.log("AuditContract verified successfully");
  } catch (error) {
    console.error("Error verifying AuditContract:", error.message);
  }
  
  // FileRegistry verification with library linking
  try {
    await hre.run("verify:verify", {
      address: contracts.FileRegistry,
      constructorArguments: [deploymentInfo.admin, 100 * 1024 * 1024], // 100 MB
      libraries: {
        FileStructs: contracts.FileStructs
      }
    });
    console.log("FileRegistry verified successfully");
  } catch (error) {
    console.error("Error verifying FileRegistry:", error.message);
  }
  
  // TransferContract verification with library linking
  try {
    await hre.run("verify:verify", {
      address: contracts.TransferContract,
      constructorArguments: [
        contracts.FileRegistry,
        contracts.AuditContract,
        deploymentInfo.admin
      ],
      libraries: {
        FileStructs: contracts.FileStructs,
        TransferStructs: contracts.TransferStructs
      }
    });
    console.log("TransferContract verified successfully");
  } catch (error) {
    console.error("Error verifying TransferContract:", error.message);
  }
  
  console.log("\nVerification process completed!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });