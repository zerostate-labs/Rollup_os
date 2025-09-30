// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRiscZeroVerifier} from "./IRiscZeroVerifier.sol";

/// @title Settlement
/// @notice Anchors the rollup's canonical state root on L1 by verifying zkVM proofs
/// @dev Phase 0: derives state root as keccak256(journal). Swap to real decoding later.
contract Settlement {
    /// @notice External zkVM verifier (e.g., RiscZero/SP1)
    IRiscZeroVerifier public immutable verifier;

    /// @notice Authorized relayer/bridge that submits proofs
    address public immutable relayer;

    /// @notice Latest finalized canonical state root for the rollup
    bytes32 public latestStateRoot;

    /// @notice Prevents re-submission of the same proof
    mapping(bytes32 => bool) public consumedProofIds;

    /// @notice Emitted when the canonical state is updated
    event StateUpdated(bytes32 indexed oldRoot, bytes32 indexed newRoot, bytes32 indexed proofId, address relayer);

    /// @param _verifier Address of the zkVM verifier contract
    /// @param _relayer Address authorized to submit proofs
    /// @param _genesisRoot Initial canonical state root
    constructor(address _verifier, address _relayer, bytes32 _genesisRoot) {
        require(_verifier != address(0), "invalid verifier");
        require(_relayer != address(0), "invalid relayer");
        verifier = IRiscZeroVerifier(_verifier);
        relayer = _relayer;
        latestStateRoot = _genesisRoot;
    }

    /// @notice Submit a rollup state update backed by a zk proof
    /// @dev For Phase 0, `journal` is hashed to derive the new root. Replace with decoding later.
    /// @param expectedOldRoot Caller-supplied last root; must equal `latestStateRoot`
    /// @param proof ZK proof bytes produced by the prover
    /// @param journal Journal/public output; must commit to the new state root
    /// @param proofId Unique identifier for replay protection (e.g., keccak256(proof||journal))
    function submitStateUpdate(
        bytes32 expectedOldRoot,
        bytes calldata proof,
        bytes calldata journal,
        bytes32 proofId
    ) external returns (bool) {
        require(msg.sender == relayer, "unauthorized");
        require(expectedOldRoot == latestStateRoot, "stale old root");
        require(!consumedProofIds[proofId], "replay");

        // Must revert if verification fails
        verifier.verify(proof, journal);

        // Phase 0: treat the journal as bytes to hash into a pseudo state root
        bytes32 newRoot = keccak256(journal);

        consumedProofIds[proofId] = true;
        bytes32 oldRoot = latestStateRoot;
        latestStateRoot = newRoot;

        emit StateUpdated(oldRoot, newRoot, proofId, msg.sender);
        return true;
    }
}


