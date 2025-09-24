// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRiscZeroVerifier} from "../IRiscZeroVerifier.sol";

/// @title MockRiscZeroVerifier
/// @notice Development-only mock that "verifies" any proof
contract MockRiscZeroVerifier is IRiscZeroVerifier {
    bool public shouldRevert;

    function setShouldRevert(bool v) external {
        shouldRevert = v;
    }

    function verify(bytes calldata /*proof*/, bytes calldata /*journal*/) external view override {
        require(!shouldRevert, "mock: verification failed");
    }
}


