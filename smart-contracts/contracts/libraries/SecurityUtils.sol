// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title SecurityUtils
 * @dev Library with utility functions for security operations
 */
library SecurityUtils {
    /**
     * @dev Generates a proof of delivery hash
     * @param transferId ID of the transfer
     * @param fileId ID of the file
     * @param recipient Address of the recipient
     * @param timestamp Time of completion
     * @return hash Proof of delivery hash
     */
    function generateProofOfDelivery(
        bytes32 transferId,
        bytes32 fileId,
        address recipient,
        uint256 timestamp
    ) internal pure returns (bytes32 hash) {
        return keccak256(abi.encodePacked(
            transferId,
            fileId,
            recipient,
            timestamp
        ));
    }
    
    /**
     * @dev Verifies a signature against a message hash
     * @param messageHash Hash of the message that was signed
     * @param signature The signature to verify
     * @param signer Expected signer address
     * @return isValid Whether signature is valid
     */
    function verifySignature(
        bytes32 messageHash,
        bytes memory signature,
        address signer
    ) internal pure returns (bool isValid) {
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        
        return recoverSigner(ethSignedMessageHash, signature) == signer;
    }
    
    /**
     * @dev Gets Ethereum signed message hash
     * @param messageHash Original message hash
     * @return Ethereum signed message hash
     */
    function getEthSignedMessageHash(bytes32 messageHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            messageHash
        ));
    }
    
    /**
     * @dev Recovers the signer from a signature
     * @param ethSignedMessageHash Ethereum signed message hash
     * @param signature Signature to recover from
     * @return signer Address of the signer
     */
    function recoverSigner(
        bytes32 ethSignedMessageHash,
        bytes memory signature
    ) internal pure returns (address signer) {
        require(signature.length == 65, "Invalid signature length");
        
        bytes32 r;
        bytes32 s;
        uint8 v;
        
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
        
        if (v < 27) {
            v += 27;
        }
        
        require(v == 27 || v == 28, "Invalid signature recovery value");
        
        return ecrecover(ethSignedMessageHash, v, r, s);
    }
    
    /**
     * @dev Validates an IPFS content identifier hash
     * @param contentHash Hash to validate
     * @return isValid Whether the hash follows IPFS format
     */
    function isValidIpfsHash(bytes32 contentHash) internal pure returns (bool isValid) {
        // Simple validation - actual implementation would check format more thoroughly
        return contentHash != bytes32(0);
    }
    
    /**
     * @dev Computes a secure hash for file chunking
     * @param fileId ID of the file
     * @param chunkIndex Index of the chunk
     * @param chunkData Chunk data
     * @return Hash of the chunk
     */
    function computeChunkHash(
        bytes32 fileId,
        uint256 chunkIndex,
        bytes memory chunkData
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(fileId, chunkIndex, chunkData));
    }
}