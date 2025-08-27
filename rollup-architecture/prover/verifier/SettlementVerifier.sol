// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title SettlementVerifier
 * @dev Verifies RISC Zero proofs and manages rollup state
 */
contract SettlementVerifier is Ownable {
    // RISC Zero verifier interface
    interface IRiscZeroVerifier {
        function verify(bytes calldata seal, bytes32 imageId, bytes calldata postStateDigest, bytes calldata journal) external view returns (bool);
    }

    // Events
    event StateUpdated(
        uint64 indexed blockNumber,
        bytes32 indexed priorStateRoot,
        bytes32 indexed postStateRoot,
        bytes32 blobRoot,
        uint32 programVersion
    );

    event BlobstreamUpdated(
        bytes32 indexed blobRoot,
        uint64 indexed celestiaHeight,
        uint256 timestamp
    );

    // State variables
    IRiscZeroVerifier public immutable riscZeroVerifier;
    bytes32 public immutable METHOD_ID; // RISC Zero method ID for our guest program
    
    // Rollup state
    mapping(uint64 => bytes32) public stateRoots; // blockNumber => stateRoot
    uint64 public latestBlockNumber;
    
    // Blobstream state (simplified - in production this would be a separate contract)
    mapping(bytes32 => bool) public committedBlobs; // blobRoot => isCommitted
    mapping(bytes32 => uint64) public blobHeights; // blobRoot => celestiaHeight
    
    // Configuration
    uint256 public constant DA_CONFIRMATION_DELAY = 100; // blocks to wait for DA confirmation
    mapping(bytes32 => uint256) public blobCommitTimestamps; // blobRoot => commit timestamp

    constructor(address _riscZeroVerifier, bytes32 _methodId) Ownable(msg.sender) {
        riscZeroVerifier = IRiscZeroVerifier(_riscZeroVerifier);
        METHOD_ID = _methodId;
    }

    /**
     * @dev Verify a RISC Zero proof and update state
     * @param receipt The RISC Zero receipt (proof)
     * @param journal The public outputs from the guest program
     */
    function verifyAndSet(bytes calldata receipt, bytes calldata journal) external {
        // Decode the journal to get public outputs
        PublicOutputs memory outputs = decodeJournal(journal);
        
        // Verify the RISC Zero proof
        bool isValid = riscZeroVerifier.verify(
            receipt, // seal
            METHOD_ID, // imageId
            outputs.post_state_root, // postStateDigest
            journal // journal
        );
        require(isValid, "Invalid RISC Zero proof");

        // Verify program version compatibility
        require(outputs.program_version == 1, "Unsupported program version");

        // Verify block number is sequential
        require(outputs.block_number == latestBlockNumber + 1, "Non-sequential block");

        // Verify prior state root matches
        require(outputs.prior_state_root == stateRoots[latestBlockNumber], "Prior state root mismatch");

        // Verify blob is committed (with optional delay)
        require(isBlobCommitted(outputs.blob_root), "Blob not committed");

        // Update state
        stateRoots[outputs.block_number] = outputs.post_state_root;
        latestBlockNumber = outputs.block_number;

        // Emit event
        emit StateUpdated(
            outputs.block_number,
            outputs.prior_state_root,
            outputs.post_state_root,
            outputs.blob_root,
            outputs.program_version
        );
    }

    /**
     * @dev Commit a blob root (simplified - in production this would come from Blobstream)
     * @param blobRoot The blob root to commit
     * @param celestiaHeight The Celestia height where the blob was posted
     */
    function commitBlob(bytes32 blobRoot, uint64 celestiaHeight) external onlyOwner {
        require(!committedBlobs[blobRoot], "Blob already committed");
        
        committedBlobs[blobRoot] = true;
        blobHeights[blobRoot] = celestiaHeight;
        blobCommitTimestamps[blobRoot] = block.timestamp;

        emit BlobstreamUpdated(blobRoot, celestiaHeight, block.timestamp);
    }

    /**
     * @dev Check if a blob is committed and has passed the confirmation delay
     */
    function isBlobCommitted(bytes32 blobRoot) public view returns (bool) {
        if (!committedBlobs[blobRoot]) {
            return false;
        }
        
        // Check if enough time has passed for DA confirmation
        uint256 commitTime = blobCommitTimestamps[blobRoot];
        return (block.timestamp - commitTime) >= DA_CONFIRMATION_DELAY;
    }

    /**
     * @dev Get the current state root for a block
     */
    function getStateRoot(uint64 blockNumber) external view returns (bytes32) {
        return stateRoots[blockNumber];
    }

    /**
     * @dev Decode the journal to extract public outputs
     * Note: This is a simplified decoder. In production, you'd use a proper ABI decoder
     */
    function decodeJournal(bytes calldata journal) internal pure returns (PublicOutputs memory outputs) {
        require(journal.length >= 32 * 7 + 8, "Invalid journal length");
        
        uint256 offset = 0;
        
        // program_version (u32 = 4 bytes)
        outputs.program_version = uint32(bytes4(journal[offset:offset+4]));
        offset += 4;
        
        // prior_state_root (32 bytes)
        outputs.prior_state_root = bytes32(journal[offset:offset+32]);
        offset += 32;
        
        // post_state_root (32 bytes)
        outputs.post_state_root = bytes32(journal[offset:offset+32]);
        offset += 32;
        
        // block_number (u64 = 8 bytes)
        outputs.block_number = uint64(bytes8(journal[offset:offset+8]));
        offset += 8;
        
        // tx_root (32 bytes)
        outputs.tx_root = bytes32(journal[offset:offset+32]);
        offset += 32;
        
        // oracle_root (32 bytes)
        outputs.oracle_root = bytes32(journal[offset:offset+32]);
        offset += 32;
        
        // blob_root (32 bytes)
        outputs.blob_root = bytes32(journal[offset:offset+32]);
    }

    // Struct for decoded public outputs
    struct PublicOutputs {
        uint32 program_version;
        bytes32 prior_state_root;
        bytes32 post_state_root;
        uint64 block_number;
        bytes32 tx_root;
        bytes32 oracle_root;
        bytes32 blob_root;
    }
}
