const { expect } = require("chai");
const { ethers } = require("hardhat");
const { constants } = require("@openzeppelin/test-helpers");

describe("FileRegistry", function () {
  let FileStructs;
  let FileRegistry;
  let fileRegistry;
  let owner;
  let user1;
  let user2;
  let admin;
  
  const maxFileSize = ethers.utils.parseUnits("100", "mwei"); // 100 MB
  const testFileName = "test-document.pdf";
  const testContentHash = ethers.utils.id("test-content-hash");
  const testFileSize = ethers.utils.parseUnits("1", "mwei"); // 1 MB
  const testContentType = "application/pdf";
  
  beforeEach(async function () {
    [owner, user1, user2, admin] = await ethers.getSigners();
    
    // Deploy FileStructs library
    const FileStructsFactory = await ethers.getContractFactory("FileStructs");
    FileStructs = await FileStructsFactory.deploy();
    await FileStructs.deployed();
    
    // Deploy FileRegistry contract
    const FileRegistryFactory = await ethers.getContractFactory("FileRegistry", {
      libraries: {
        FileStructs: FileStructs.address
      }
    });
    fileRegistry = await FileRegistryFactory.deploy(owner.address, maxFileSize);
    await fileRegistry.deployed();
    
    // Grant admin role to admin account
    const ADMIN_ROLE = ethers.utils.id("ADMIN_ROLE");
    await fileRegistry.grantRole(ADMIN_ROLE, admin.address);
  });
  
  describe("File Registration", function () {
    it("Should register a new file successfully", async function () {
      const encryptionKey = ethers.utils.randomBytes(32);
      const isPublic = false;
      
      const tx = await fileRegistry.registerFile(
        testFileName,
        testContentHash,
        encryptionKey,
        testFileSize,
        testContentType,
        isPublic
      );
      
      const receipt = await tx.wait();
      const event = receipt.events.find(e => e.event === 'FileRegistered');
      expect(event).to.not.be.undefined;
      
      const fileId = event.args.fileId;
      expect(fileId).to.not.equal(constants.ZERO_BYTES32);
      
      const fileMetadata = await fileRegistry.getFileMetadata(fileId);
      expect(fileMetadata.name).to.equal(testFileName);
      expect(fileMetadata.owner).to.equal(owner.address);
      expect(fileMetadata.contentHash).to.equal(testContentHash);
      expect(fileMetadata.fileSize).to.equal(testFileSize);
      expect(fileMetadata.contentType).to.equal(testContentType);
      expect(fileMetadata.isPublic).to.equal(isPublic);
      expect(fileMetadata.isDeleted).to.equal(false);
    });
    
    it("Should fail to register a file exceeding max size", async function () {
      const encryptionKey = ethers.utils.randomBytes(32);
      const oversizedFile = maxFileSize.add(1);
      
      await expect(
        fileRegistry.registerFile(
          testFileName,
          testContentHash,
          encryptionKey,
          oversizedFile,
          testContentType,
          false
        )
      ).to.be.revertedWith("Invalid file size");
    });
    
    it("Should fail to register a file with empty name", async function () {
      const encryptionKey = ethers.utils.randomBytes(32);
      
      await expect(
        fileRegistry.registerFile(
          "",
          testContentHash,
          encryptionKey,
          testFileSize,
          testContentType,
          false
        )
      ).to.be.revertedWith("Name cannot be empty");
    });
  });
  
  describe("Access Control", function () {
    let fileId;
    
    beforeEach(async function () {
      // Register a private file first
      const encryptionKey = ethers.utils.randomBytes(32);
      const isPublic = false;
      
      const tx = await fileRegistry.registerFile(
        testFileName,
        testContentHash,
        encryptionKey,
        testFileSize,
        testContentType,
        isPublic
      );
      
      const receipt = await tx.wait();
      const event = receipt.events.find(e => e.event === 'FileRegistered');
      fileId = event.args.fileId;
    });
    
    it("Should allow owner to access file metadata", async function () {
      const fileMetadata = await fileRegistry.getFileMetadata(fileId);
      expect(fileMetadata.fileId).to.equal(fileId);
      expect(fileMetadata.owner).to.equal(owner.address);
    });
    
    it("Should prevent unauthorized access to file metadata", async function () {
      await expect(
        fileRegistry.connect(user1).getFileMetadata(fileId)
      ).to.be.revertedWith("Access denied");
    });
    
    it("Should grant and revoke access to a file", async function () {
      // Initial access check should be false
      const READ_ACCESS = 1; // From enum AccessLevel
      const initialAccess = await fileRegistry.checkAccess(fileId, user1.address, READ_ACCESS);
      expect(initialAccess).to.be.false;
      
      // Grant access
      await fileRegistry.grantAccess(
        fileId,
        user1.address,
        READ_ACCESS,
        0 // No expiration
      );
      
      // Access check should now be true
      const accessAfterGrant = await fileRegistry.checkAccess(fileId, user1.address, READ_ACCESS);
      expect(accessAfterGrant).to.be.true;
      
      // User should be able to access metadata now
      const fileMetadata = await fileRegistry.connect(user1).getFileMetadata(fileId);
      expect(fileMetadata.fileId).to.equal(fileId);
      
      // Revoke access
      await fileRegistry.revokeAccess(fileId, user1.address);
      
      // Access check should be false again
      const accessAfterRevoke = await fileRegistry.checkAccess(fileId, user1.address, READ_ACCESS);
      expect(accessAfterRevoke).to.be.false;
      
      // User should not be able to access metadata anymore
      await expect(
        fileRegistry.connect(user1).getFileMetadata(fileId)
      ).to.be.revertedWith("Access denied");
    });
    
    it("Should enforce access expiration", async function () {
      const READ_ACCESS = 1; // From enum AccessLevel
      const oneHour = 3600;
      const currentTime = Math.floor(Date.now() / 1000);
      const expirationTime = currentTime + oneHour;
      
      // Grant access with expiration
      await fileRegistry.grantAccess(
        fileId,
        user1.address,
        READ_ACCESS,
        expirationTime
      );
      
      // Access check should be true before expiration
      const accessBeforeExpiry = await fileRegistry.checkAccess(fileId, user1.address, READ_ACCESS);
      expect(accessBeforeExpiry).to.be.true;
      
      // Advance time beyond expiration
      await ethers.provider.send("evm_increaseTime", [oneHour + 1]);
      await ethers.provider.send("evm_mine");
      
      // Access check should be false after expiration
      const accessAfterExpiry = await fileRegistry.checkAccess(fileId, user1.address, READ_ACCESS);
      expect(accessAfterExpiry).to.be.false;
    });
  });
  
  describe("File Operations", function () {
    let privateFileId;
    let publicFileId;
    
    beforeEach(async function () {
      // Register a private file
      const encryptionKey = ethers.utils.randomBytes(32);
      
      let tx = await fileRegistry.registerFile(
        "private-file.pdf",
        testContentHash,
        encryptionKey,
        testFileSize,
        testContentType,
        false // private
      );
      
      let receipt = await tx.wait();
      let event = receipt.events.find(e => e.event === 'FileRegistered');
      privateFileId = event.args.fileId;
      
      // Register a public file
      tx = await fileRegistry.registerFile(
        "public-file.pdf",
        testContentHash,
        encryptionKey,
        testFileSize,
        testContentType,
        true // public
      );
      
      receipt = await tx.wait();
      event = receipt.events.find(e => e.event === 'FileRegistered');
      publicFileId = event.args.fileId;
    });
    
    it("Should allow updating file content by owner", async function () {
      const newContentHash = ethers.utils.id("updated-content-hash");
      const newEncryptionKey = ethers.utils.randomBytes(32);
      const newFileSize = ethers.utils.parseUnits("2", "mwei"); // 2 MB
      
      await fileRegistry.updateFile(
        privateFileId,
        newContentHash,
        newEncryptionKey,
        newFileSize
      );
      
      const updatedMetadata = await fileRegistry.getFileMetadata(privateFileId);
      expect(updatedMetadata.contentHash).to.equal(newContentHash);
      expect(updatedMetadata.fileSize).to.equal(newFileSize);
    });
    
    it("Should allow authorized user to update content but not encryption key", async function () {
      // Grant WRITE access to user1
      const WRITE_ACCESS = 2; // From enum AccessLevel
      await fileRegistry.grantAccess(
        privateFileId,
        user1.address,
        WRITE_ACCESS,
        0 // No expiration
      );
      
      const newContentHash = ethers.utils.id("new-content-from-user1");
      const newFileSize = ethers.utils.parseUnits("1.5", "mwei"); // 1.5 MB
      
      // User1 should be able to update content but not encryption key
      await fileRegistry.connect(user1).updateFile(
        privateFileId,
        newContentHash,
        [], // Empty encryption key (no change)
        newFileSize
      );
      
      const updatedMetadata = await fileRegistry.getFileMetadata(privateFileId);
      expect(updatedMetadata.contentHash).to.equal(newContentHash);
      expect(updatedMetadata.fileSize).to.equal(newFileSize);
      
      // User1 trying to update encryption key should fail
      const newEncryptionKey = ethers.utils.randomBytes(32);
      await expect(
        fileRegistry.connect(user1).updateFile(
          privateFileId,
          newContentHash,
          newEncryptionKey,
          newFileSize
        )
      ).to.be.revertedWith("Only owner can change encryption key");
    });
    
    it("Should allow logical deletion of file by owner", async function () {
      await fileRegistry.deleteFile(privateFileId);
      
      const metadata = await fileRegistry.getFileMetadata(privateFileId);
      expect(metadata.isDeleted).to.be.true;
      
      // Deleted files should not be accessible to other users
      const READ_ACCESS = 1;
      await fileRegistry.grantAccess(
        privateFileId,
        user1.address,
        READ_ACCESS,
        0
      );
      
      const accessToDeletedFile = await fileRegistry.checkAccess(
        privateFileId,
        user1.address,
        READ_ACCESS
      );
      expect(accessToDeletedFile).to.be.false;
    });
    
    it("Should allow admin to delete any file", async function () {
      await fileRegistry.connect(admin).deleteFile(publicFileId);
      
      const metadata = await fileRegistry.getFileMetadata(publicFileId);
      expect(metadata.isDeleted).to.be.true;
    });
    
    it("Should prevent non-owners from deleting files", async function () {
      await expect(
        fileRegistry.connect(user1).deleteFile(privateFileId)
      ).to.be.revertedWith("Not authorized");
    });
  });
  
  describe("Administrative Functions", function () {
    it("Should allow admin to set max file size", async function () {
      const newMaxSize = ethers.utils.parseUnits("200", "mwei"); // 200 MB
      
      await fileRegistry.connect(admin).setMaxFileSize(newMaxSize);
      
      // Check that the max file size was updated
      expect(await fileRegistry.maxFileSize()).to.equal(newMaxSize);
      
      // Should be able to register a file with the new larger size
      const encryptionKey = ethers.utils.randomBytes(32);
      const largerFileSize = ethers.utils.parseUnits("150", "mwei"); // 150 MB
      
      await fileRegistry.registerFile(
        testFileName,
        testContentHash,
        encryptionKey,
        largerFileSize,
        testContentType,
        false
      );
    });
    
    it("Should allow admin to pause and unpause the contract", async function () {
      // Pause the contract
      await fileRegistry.connect(admin).pause();
      
      // Operations should be paused
      const encryptionKey = ethers.utils.randomBytes(32);
      await expect(
        fileRegistry.registerFile(
          testFileName,
          testContentHash,
          encryptionKey,
          testFileSize,
          testContentType,
          false
        )
      ).to.be.revertedWith("Pausable: paused");
      
      // Unpause the contract
      await fileRegistry.connect(admin).unpause();
      
      // Operations should work again
      await fileRegistry.registerFile(
        testFileName,
        testContentHash,
        encryptionKey,
        testFileSize,
        testContentType,
        false
      );
    });
    
    it("Should prevent non-admins from calling admin functions", async function () {
      await expect(
        fileRegistry.connect(user1).setMaxFileSize(1000000)
      ).to.be.revertedWith("AccessControl");
      
      await expect(
        fileRegistry.connect(user1).pause()
      ).to.be.revertedWith("AccessControl");
    });
  });
  
  describe("User File Management", function () {
    it("Should track files owned by users", async function () {
      // Register multiple files for owner
      const encryptionKey = ethers.utils.randomBytes(32);
      
      for (let i = 0; i < 3; i++) {
        await fileRegistry.registerFile(
          `file-${i}.pdf`,
          ethers.utils.id(`content-${i}`),
          encryptionKey,
          testFileSize,
          testContentType,
          false
        );
      }
      
      // Get user files
      const userFiles = await fileRegistry.getUserFiles(owner.address);
      expect(userFiles.length).to.equal(3);
    });
    
    it("Should handle public file access correctly", async function () {
      // Register a public file
      const encryptionKey = ethers.utils.randomBytes(32);
      
      const tx = await fileRegistry.registerFile(
        "public-document.pdf",
        testContentHash,
        encryptionKey,
        testFileSize,
        testContentType,
        true // public
      );
      
      const receipt = await tx.wait();
      const event = receipt.events.find(e => e.event === 'FileRegistered');
      const fileId = event.args.fileId;
      
      // Any user should be able to access metadata of public file
      const READ_ACCESS = 1;
      const hasAccess = await fileRegistry.checkAccess(fileId, user1.address, READ_ACCESS);
      expect(hasAccess).to.be.true;
      
      // User should be able to get metadata
      const metadata = await fileRegistry.connect(user1).getFileMetadata(fileId);
      expect(metadata.name).to.equal("public-document.pdf");
      
      // But encryption key should be empty for non-owners
      expect(metadata.encryptionKey).to.equal("0x");
      
      // Owner should still see the encryption key
      const ownerView = await fileRegistry.getFileMetadata(fileId);
      expect(ownerView.encryptionKey).to.not.equal("0x");
      
      // Public access should only grant READ access, not WRITE
      const WRITE_ACCESS = 2;
      const hasWriteAccess = await fileRegistry.checkAccess(fileId, user1.address, WRITE_ACCESS);
      expect(hasWriteAccess).to.be.false;
    });
  });
});