const { expect } = require("chai");
const { ethers } = require("hardhat");
const { constants } = require("@openzeppelin/test-helpers");

describe("TransferContract", function () {
  let FileStructs;
  let TransferStructs;
  let FileRegistry;
  let TransferContract;
  let AuditContract;
  
  let fileRegistry;
  let transferContract;
  let auditContract;
  
  let owner;
  let sender;
  let recipient;
  let admin;
  
  let fileId;
  const maxFileSize = ethers.utils.parseUnits("100", "mwei"); // 100 MB
  const testFileName = "transfer-test-document.pdf";
  const testContentHash = ethers.utils.id("test-content-hash");
  const testFileSize = ethers.utils.parseUnits("1", "mwei"); // 1 MB
  const testContentType = "application/pdf";
  
  beforeEach(async function () {
    [owner, sender, recipient, admin] = await ethers.getSigners();
    
    // Deploy libraries
    const FileStructsFactory = await ethers.getContractFactory("FileStructs");
    FileStructs = await FileStructsFactory.deploy();
    await FileStructs.deployed();
    
    const TransferStructsFactory = await ethers.getContractFactory("TransferStructs");
    TransferStructs = await TransferStructsFactory.deploy();
    await TransferStructs.deployed();
    
    // Deploy AuditContract
    const AuditContractFactory = await ethers.getContractFactory("AuditContract");
    auditContract = await AuditContractFactory.deploy(owner.address);
    await auditContract.deployed();
    
    // Deploy FileRegistry
    const FileRegistryFactory = await ethers.getContractFactory("FileRegistry", {
      libraries: {
        FileStructs: FileStructs.address
      }
    });
    fileRegistry = await FileRegistryFactory.deploy(owner.address, maxFileSize);
    await fileRegistry.deployed();
    
    // Deploy TransferContract
    const TransferContractFactory = await ethers.getContractFactory("TransferContract", {
      libraries: {
        FileStructs: FileStructs.address,
        TransferStructs: TransferStructs.address
      }
    });
    transferContract = await TransferContractFactory.deploy(
      fileRegistry.address,
      auditContract.address,
      owner.address
    );
    await transferContract.deployed();
    
    // Grant roles
    const ADMIN_ROLE = ethers.utils.id("ADMIN_ROLE");
    await fileRegistry.grantRole(ADMIN_ROLE, admin.address);
    await transferContract.grantRole(ADMIN_ROLE, admin.address);
    
    const RECORDER_ROLE = ethers.utils.id("RECORDER_ROLE");
    await auditContract.grantRole(RECORDER_ROLE, transferContract.address);
    
    // Register a test file as sender
    await fileRegistry.connect(sender).registerFile(
      testFileName,
      testContentHash,
      ethers.utils.randomBytes(32), // encryption key
      testFileSize,
      testContentType,
      false // private
    );
    
    // Get the file ID
    const userFiles = await fileRegistry.getUserFiles(sender.address);
    fileId = userFiles[0];
  });
  
  describe("Transfer Initiation", function () {
    it("Should initiate a file transfer successfully", async function () {
      const message = "Please review this document";
      const READ_ACCESS = 1;
      
      const tx = await transferContract.connect(sender).initiateTransfer(
        fileId,
        recipient.address,
        message,
        0, // default deadline
        READ_ACCESS
      );
      
      const receipt = await tx.wait();
      const event = receipt.events.find(e => e.event === 'TransferInitiated');
      expect(event).to.not.be.undefined;
      
      const transferId = event.args.transferId;
      expect(transferId).to.not.equal(constants.ZERO_BYTES32);
      
      // Verify transfer details
      const transfer = await transferContract.connect(sender).getTransfer(transferId);
      expect(transfer.fileId).to.equal(fileId);
      expect(transfer.sender).to.equal(sender.address);
      expect(transfer.recipient).to.equal(recipient.address);
      expect(transfer.message).to.equal(message);
      expect(transfer.status).to.equal(1); // INITIATED
      expect(transfer.accessLevel).to.equal(READ_ACCESS);
    });
    
    it("Should fail to initiate transfer to invalid recipient", async function () {
      await expect(
        transferContract.connect(sender).initiateTransfer(
          fileId,
          constants.ZERO_ADDRESS,
          "",
          0,
          1 // READ_ACCESS
        )
      ).to.be.revertedWith("Invalid recipient");
    });
    
    it("Should fail to initiate transfer to self", async function () {
      await expect(
        transferContract.connect(sender).initiateTransfer(
          fileId,
          sender.address,
          "",
          0,
          1 // READ_ACCESS
        )
      ).to.be.revertedWith("Cannot transfer to self");
    });
    
    it("Should fail to initiate transfer without file access", async function () {
      // Try to transfer a file that user doesn't have access to
      const nonExistentFileId = ethers.utils.id("non-existent-file");
      
      await expect(
        transferContract.connect(sender).initiateTransfer(
          nonExistentFileId,
          recipient.address,
          "",
          0,
          1 // READ_ACCESS
        )
      ).to.be.revertedWith("No access to file");
    });
  });
  
  describe("Transfer Lifecycle", function () {
    let transferId;
    
    beforeEach(async function () {
      // Initiate a transfer
      const tx = await transferContract.connect(sender).initiateTransfer(
        fileId,
        recipient.address,
        "Please review this document",
        0, // default deadline
        1 // READ_ACCESS
      );
      
      const receipt = await tx.wait();
      const event = receipt.events.find(e => e.event === 'TransferInitiated');
      transferId = event.args.transferId;
    });
    
    it("Should allow recipient to accept a transfer", async function () {
      await transferContract.connect(recipient).acceptTransfer(transferId);
      
      const transfer = await transferContract.connect(recipient).getTransfer(transferId);
      expect(transfer.status).to.equal(2); // IN_PROGRESS
    });
    
    it("Should allow recipient to reject a transfer", async function () {
      const rejectReason = "Not needed at this time";
      await transferContract.connect(recipient).rejectTransfer(transferId, rejectReason);
      
      const transfer = await transferContract.connect(recipient).getTransfer(transferId);
      expect(transfer.status).to.equal(4); // REJECTED
    });
    
    it("Should allow sender to cancel a pending transfer", async function () {
      await transferContract.connect(sender).cancelTransfer(transferId);
      
      const transfer = await transferContract.connect(sender).getTransfer(transferId);
      expect(transfer.status).to.equal(5); // CANCELLED
    });
    
    it("Should complete the transfer process successfully", async function () {
      // Accept transfer
      await transferContract.connect(recipient).acceptTransfer(transferId);
      
      // Complete transfer
      const proofOfDelivery = ethers.utils.id("proof-of-receipt");
      await transferContract.connect(recipient).completeTransfer(transferId, proofOfDelivery);
      
      // Check transfer status
      const transfer = await transferContract.connect(recipient).getTransfer(transferId);
      expect(transfer.status).to.equal(3); // COMPLETED
      expect(transfer.proofOfDelivery).to.equal(proofOfDelivery);
      expect(transfer.completedAt).to.not.equal(0);
      
      // Verify that recipient has access to the file
      const READ_ACCESS = 1;
      const hasAccess = await fileRegistry.checkAccess(
        fileId,
        recipient.address,
        READ_ACCESS
      );
      expect(hasAccess).to.be.true;
    });
    
    it("Should handle transfer expiration", async function () {
      // Set short expiration time
      const oneHour = 3600;
      await transferContract.connect(admin).setTransferExpirationTime(oneHour);
      
      // Initiate a new transfer
      const tx = await transferContract.connect(sender).initiateTransfer(
        fileId,
        recipient.address,
        "Expires soon",
        0, // use default expiration
        1 // READ_ACCESS
      );
      
      const receipt = await tx.wait();
      const event = receipt.events.find(e => e.event === 'TransferInitiated');
      const shortExpiryTransferId = event.args.transferId;
      
      // Advance time beyond expiration
      await ethers.provider.send("evm_increaseTime", [oneHour + 1]);
      await ethers.provider.send("evm_mine");
      
      // Attempt to accept expired transfer
      await expect(
        transferContract.connect(recipient).acceptTransfer(shortExpiryTransferId)
      ).to.be.revertedWith("Transfer expired");
    });
  });
  
  describe("Dispute Handling", function () {
    let transferId;
    
    beforeEach(async function () {
      // Initiate and accept a transfer
      const tx = await transferContract.connect(sender).initiateTransfer(
        fileId,
        recipient.address,
        "Document for review",
        0,
        1 // READ_ACCESS
      );
      
      const receipt = await tx.wait();
      const event = receipt.events.find(e => e.event === 'TransferInitiated');
      transferId = event.args.transferId;
      
      await transferContract.connect(recipient).acceptTransfer(transferId);
    });
    
    it("Should allow sender to raise a dispute", async function () {
      const disputeReason = "File appears corrupted";
      await transferContract.connect(sender).disputeTransfer(transferId, disputeReason);
      
      const transfer = await transferContract.connect(sender).getTransfer(transferId);
      expect(transfer.status).to.equal(6); // DISPUTED
      expect(transfer.disputeReason).to.equal(disputeReason);
    });
    
    it("Should allow recipient to raise a dispute", async function () {
      const disputeReason = "Cannot access file content";
      await transferContract.connect(recipient).disputeTransfer(transferId, disputeReason);
      
      const transfer = await transferContract.connect(recipient).getTransfer(transferId);
      expect(transfer.status).to.equal(6); // DISPUTED
      expect(transfer.disputeReason).to.equal(disputeReason);
    });
    
    it("Should allow admin to resolve a dispute as completed", async function () {
      // Raise dispute
      await transferContract.connect(recipient).disputeTransfer(transferId, "Access issues");
      
      // Resolve as completed
      const COMPLETED_RESOLUTION = 1;
      await transferContract.connect(admin).resolveDispute(transferId, COMPLETED_RESOLUTION);
      
      const transfer = await transferContract.connect(admin).getTransfer(transferId);
      expect(transfer.status).to.equal(3); // COMPLETED
      expect(transfer.resolution).to.equal(COMPLETED_RESOLUTION);
      
      // Check that recipient received access
      const READ_ACCESS = 1;
      const hasAccess = await fileRegistry.checkAccess(fileId, recipient.address, READ_ACCESS);
      expect(hasAccess).to.be.true;
    });
    
    it("Should allow admin to resolve a dispute as cancelled", async function () {
      // Raise dispute
      await transferContract.connect(sender).disputeTransfer(transferId, "Sent in error");
      
      // Resolve as cancelled
      const CANCELLED_RESOLUTION = 2;
      await transferContract.connect(admin).resolveDispute(transferId, CANCELLED_RESOLUTION);
      
      const transfer = await transferContract.connect(admin).getTransfer(transferId);
      expect(transfer.status).to.equal(5); // CANCELLED
      expect(transfer.resolution).to.equal(CANCELLED_RESOLUTION);
    });
    
    it("Should prevent non-admins from resolving disputes", async function () {
      // Raise dispute
      await transferContract.connect(recipient).disputeTransfer(transferId, "Access issues");
      
      // Attempt to resolve without admin role
      const COMPLETED_RESOLUTION = 1;
      await expect(
        transferContract.connect(sender).resolveDispute(transferId, COMPLETED_RESOLUTION)
      ).to.be.revertedWith("AccessControl");
    });
  });
  
  describe("User Transfer Management", function () {
    it("Should track sent and received transfers", async function () {
      // Initiate multiple transfers
      for (let i = 0; i < 3; i++) {
        await transferContract.connect(sender).initiateTransfer(
          fileId,
          recipient.address,
          `Transfer ${i}`,
          0,
          1 // READ_ACCESS
        );
      }
      
      // Check sender's transfers
      const sentTransfers = await transferContract.connect(sender).getUserSentTransfers(sender.address);
      expect(sentTransfers.length).to.equal(3);
      
      // Check recipient's transfers
      const receivedTransfers = await transferContract.connect(recipient).getUserReceivedTransfers(recipient.address);
      expect(receivedTransfers.length).to.equal(3);
    });
    
    it("Should enforce privacy of transfer records", async function () {
      // Initiate a transfer
      await transferContract.connect(sender).initiateTransfer(
        fileId,
        recipient.address,
        "Confidential document",
        0,
        1 // READ_ACCESS
      );
      
      // Third party should not be able to view sent transfers
      await expect(
        transferContract.connect(admin).getUserSentTransfers(sender.address)
      ).to.be.revertedWith("Not authorized");
      
      // Admin should be authorized to view transfer records
      const OPERATOR_ROLE = ethers.utils.id("OPERATOR_ROLE");
      await transferContract.grantRole(OPERATOR_ROLE, admin.address);
      
      // Now admin should be able to view records
      const sentTransfers = await transferContract.connect(admin).getUserSentTransfers(sender.address);
      expect(sentTransfers.length).to.equal(1);
    });
  });
  
  describe("Administrative Functions", function () {
    it("Should allow admin to update contract references", async function () {
      // Deploy a new FileRegistry
      const newFileRegistryFactory = await ethers.getContractFactory("FileRegistry", {
        libraries: {
          FileStructs: FileStructs.address
        }
      });
      const newFileRegistry = await newFileRegistryFactory.deploy(owner.address, maxFileSize);
      await newFileRegistry.deployed();
      
      // Update reference
      await transferContract.connect(admin).setFileRegistry(newFileRegistry.address);
      
      // Deploy a new AuditContract
      const newAuditContractFactory = await ethers.getContractFactory("AuditContract");
      const newAuditContract = await newAuditContractFactory.deploy(owner.address);
      await newAuditContract.deployed();
      
      // Update reference
      await transferContract.connect(admin).setAuditContract(newAuditContract.address);
    });
    
    it("Should allow admin to pause and unpause the contract", async function () {
      // Pause the contract
      await transferContract.connect(admin).pause();
      
      // Operations should be paused
      await expect(
        transferContract.connect(sender).initiateTransfer(
          fileId,
          recipient.address,
          "Test message",
          0,
          1 // READ_ACCESS
        )
      ).to.be.revertedWith("Pausable: paused");
      
      // Unpause the contract
      await transferContract.connect(admin).unpause();
      
      // Operations should work again
      await transferContract.connect(sender).initiateTransfer(
        fileId,
        recipient.address,
        "Test message",
        0,
        1 // READ_ACCESS
      );
    });
  });
});