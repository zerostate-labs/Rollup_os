// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRiscZeroVerifier} from "./IRiscZeroVerifier.sol";

/// @title SettlementVerifier
/// @notice Verifies zk proofs and anchors the rollup state on L1
/// @dev Uses an external zkVM verifier (e.g., RiscZero) to validate proofs
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
    event ProofVerified(bytes32 indexed stateRoot, bytes32 indexed proofId, address indexed relayer);

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
    /// @param proof ZK proof bytes
    /// @param journal Journal bytes committed by the zkVM (includes state root)
    /// @param proofId Unique identifier to prevent replay (e.g., keccak(proof||journal))
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

        emit ProofVerified(stateRoot, proofId, msg.sender);
        return true;
    }
}


