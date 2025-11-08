// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRiscZeroVerifier} from "./IRiscZeroVerifier.sol";

/// @title SettlementVerifier
/// @notice Verifies zk proofs and anchors the rollup state on L1
/// @dev Uses an external zkVM verifier (e.g., RiscZero) to validate proofs
/// @dev Finality: This contract should only be called after the L1 block containing
///      the rollup data is finalized. Use checkFinality.js script to verify finality
///      before submitting proofs. On Ethereum PoS, finality occurs ~12.8 minutes
///      after block inclusion (2 epochs × 32 slots × 12 seconds).
contract SettlementVerifier {
    /// @notice Address of the zkVM verifier contract
    IRiscZeroVerifier public immutable verifier;

    /// @notice Address allowed to submit proofs (e.g., bridge/relayer)
    address public immutable relayer;

    /// @notice Latest verified canonical state root
    bytes32 public latestStateRoot;

    /// @notice Mapping of used proof identifiers to prevent replay
    mapping(bytes32 => bool) public consumedProofIds;

    /// @notice Emitted when a proof is verified and state is updated
    /// @param stateRoot The new state root after verification
    /// @param proofId Unique identifier for the proof (prevents replay)
    /// @param relayer Address that submitted the proof
    /// @param l1BlockNumber The L1 block number where this verification occurred
    event ProofVerified(
        bytes32 indexed stateRoot,
        bytes32 indexed proofId,
        address indexed relayer,
        uint256 l1BlockNumber
    );

    /// @param _verifier Address of the zkVM verifier (e.g., RiscZero verifier)
    /// @param _relayer Authorized relayer/bridge address
    constructor(address _verifier, address _relayer) {
        require(_verifier != address(0), "invalid verifier");
        require(_relayer != address(0), "invalid relayer");
        verifier = IRiscZeroVerifier(_verifier);
        relayer = _relayer;
    }

    /// @notice Verify zk proof from the rollup and update canonical state
    /// @dev The journal must contain the new state commitment (e.g., state root)
    /// @dev IMPORTANT: This function should only be called after the L1 block containing
    ///      the rollup data is finalized. The relayer script should check finality
    ///      using checkFinality.js before calling this function.
    /// @param proof ZK proof bytes
    /// @param journal Journal bytes committed by the zkVM (includes state root)
    /// @param proofId Unique identifier to prevent replay (e.g., keccak(proof||journal))
    /// @return true if verification succeeds
    function verifyProof(bytes calldata proof, bytes calldata journal, bytes32 proofId) external returns (bool) {
        require(msg.sender == relayer, "unauthorized");
        require(!consumedProofIds[proofId], "replay");

        // Verify the proof against the journal using the external verifier
        // If verification fails, the external call MUST revert
        verifier.verify(proof, journal);

        // Derive state root from the journal (application-specific encoding)
        // For Phase 0, we derive it as keccak(journal)
        bytes32 stateRoot = keccak256(journal);

        // Mark proof as consumed and update canonical root
        consumedProofIds[proofId] = true;
        latestStateRoot = stateRoot;

        // Emit event with L1 block number for finality tracking
        emit ProofVerified(stateRoot, proofId, msg.sender, block.number);
        return true;
    }
}


