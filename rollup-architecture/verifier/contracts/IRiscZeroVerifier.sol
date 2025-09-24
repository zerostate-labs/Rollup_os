// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IRiscZeroVerifier
/// @notice Minimal interface for a RISC Zero verifier contract
interface IRiscZeroVerifier {
    /// @notice Verify a RISC Zero proof against a journal (public output)
    /// @param proof ZK proof bytes
    /// @param journal Journal bytes representing the committed public output
    function verify(bytes calldata proof, bytes calldata journal) external view;
}


