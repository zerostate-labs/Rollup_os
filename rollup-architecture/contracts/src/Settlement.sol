// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Settlement Contract for ZeroState Rollup
/// @notice Manages state root transitions and proof verification for the rollup
/// @dev Phase 0: Uses keccak256 as stub verifier, will be replaced with RiscZero/SP1
contract Settlement {
    /// @notice Latest finalized state root of the rollup
    bytes32 public latestStateRoot;
    
    /// @notice Block number corresponding to the latest state root
    uint256 public latestBlockNumber;
    
    /// @notice Mapping to prevent proof replay attacks
    /// @dev Maps keccak256(oldRoot, newRoot, blockNumber) => bool
    mapping(bytes32 => bool) public usedProofs;
    
    /// @notice Address authorized to submit state updates (sequencer/prover)
    address public sequencer;
    
    /// @notice Emitted when a new state root is finalized
    /// @param blockNumber The rollup block number
    /// @param oldStateRoot Previous state root
    /// @param newStateRoot New state root after applying transactions
    /// @param prover Address that submitted the proof
    event StateRootUpdated(
        uint256 indexed blockNumber,
        bytes32 oldStateRoot,
        bytes32 newStateRoot,
        address indexed prover
    );
    
    /// @notice Emitted when sequencer address is updated
    event SequencerUpdated(address indexed oldSequencer, address indexed newSequencer);
    
    /// @notice Constructor initializes the contract with genesis state
    /// @param _initialStateRoot The genesis state root
    /// @param _sequencer Address authorized to submit proofs
    constructor(bytes32 _initialStateRoot, address _sequencer) {
        require(_sequencer != address(0), "Invalid sequencer address");
        latestStateRoot = _initialStateRoot;
        latestBlockNumber = 0;
        sequencer = _sequencer;
        
        emit StateRootUpdated(0, bytes32(0), _initialStateRoot, msg.sender);
    }
    
    /// @notice Submit a new state update with proof
    /// @dev Phase 0: Uses keccak256(proof) as stub verification
    /// @param oldRoot Previous state root (must match current latestStateRoot)
    /// @param newRoot New state root after applying transactions
    /// @param blockNumber Rollup block number for this update
    /// @param proof ZK proof (stub for Phase 0, will be real zkSNARK/zkSTARK later)
    function submitStateUpdate(
        bytes32 oldRoot,
        bytes32 newRoot,
        uint256 blockNumber,
        bytes calldata proof
    ) external returns (bool) {
        // Authorization check
        require(msg.sender == sequencer, "Unauthorized: only sequencer can submit");
        
        // State continuity check
        require(oldRoot == latestStateRoot, "Invalid old root: does not match current state");
        
        // Block number must be sequential
        require(blockNumber == latestBlockNumber + 1, "Invalid block number: must be sequential");
        
        // Proof replay protection
        bytes32 proofId = keccak256(abi.encodePacked(oldRoot, newRoot, blockNumber));
        require(!usedProofs[proofId], "Proof replay detected");
        
        // Phase 0 Stub Verification: keccak256(proof) must not be zero
        // In production, this will call RiscZero/SP1 verifier contract
        require(proof.length > 0, "Empty proof");
        bytes32 proofHash = keccak256(proof);
        require(proofHash != bytes32(0), "Invalid proof hash");
        
        // TODO: Replace with real verifier call:
        // require(verifier.verify(proof, journal), "Proof verification failed");
        
        // Mark proof as used (replay protection)
        usedProofs[proofId] = true;
        
        // Update state
        latestStateRoot = newRoot;
        latestBlockNumber = blockNumber;
        
        emit StateRootUpdated(blockNumber, oldRoot, newRoot, msg.sender);
        
        return true;
    }
    
    /// @notice Get the current finalized state of the rollup
    /// @return stateRoot The latest state root
    /// @return blockNumber The latest block number
    function getLatestState() external view returns (bytes32 stateRoot, uint256 blockNumber) {
        return (latestStateRoot, latestBlockNumber);
    }
    
    /// @notice Check if a proof has been used (for replay protection)
    /// @param oldRoot Previous state root
    /// @param newRoot New state root
    /// @param blockNumber Block number
    /// @return bool True if proof has been used
    function isProofUsed(
        bytes32 oldRoot,
        bytes32 newRoot,
        uint256 blockNumber
    ) external view returns (bool) {
        bytes32 proofId = keccak256(abi.encodePacked(oldRoot, newRoot, blockNumber));
        return usedProofs[proofId];
    }
    
    /// @notice Update the sequencer address (for governance/upgrades)
    /// @param newSequencer New sequencer address
    function updateSequencer(address newSequencer) external {
        require(msg.sender == sequencer, "Unauthorized: only current sequencer");
        require(newSequencer != address(0), "Invalid address");
        
        address oldSequencer = sequencer;
        sequencer = newSequencer;
        
        emit SequencerUpdated(oldSequencer, newSequencer);
    }
    
    /// @notice Verify a historical state transition
    /// @param oldRoot Previous state root
    /// @param newRoot New state root
    /// @param blockNumber Block number
    /// @return bool True if this transition was finalized
    function verifyStateTransition(
        bytes32 oldRoot,
        bytes32 newRoot,
        uint256 blockNumber
    ) external view returns (bool) {
        bytes32 proofId = keccak256(abi.encodePacked(oldRoot, newRoot, blockNumber));
        return usedProofs[proofId];
    }
}

