# Prover Module Documentation

## Overview
The prover module is a Rust-based zero-knowledge proof system built on Risc0 ZKVM. It provides cryptographic proof generation and verification capabilities for rollup block validation, ensuring data integrity and computational correctness without revealing sensitive information.

## File Structure

```
prover/
├── .gitignore                 # Git ignore patterns for Rust/Risc0 projects
├── Cargo.toml                 # Workspace configuration
├── host/                      # Host-side prover implementation
│   ├── Cargo.toml            # Host dependencies and configuration
│   └── src/
│       └── lib.rs            # Main prover logic and API
├── methods/                   # Risc0 methods (guest code)
│   ├── build.rs              # Build script for embedding methods
│   ├── Cargo.toml            # Methods package configuration
│   ├── guest/                # Guest code (runs inside ZKVM)
│   │   ├── Cargo.lock        # Locked dependencies
│   │   ├── Cargo.toml        # Guest dependencies
│   │   └── src/
│   │       └── main.rs       # Guest program entry point
│   └── src/
│       └── lib.rs            # Generated methods interface
└── target/                    # Build artifacts (ignored by git)
```

## Detailed File Analysis

### 1. `.gitignore`
**Purpose**: Defines files and directories to be ignored by Git version control.

**Key Patterns**:
- **Rust artifacts**: `/target/`, `**/*.rs.bk`, `*.pdb`
- **IDE files**: `.vscode/`, `.idea/`, `*.swp`, `*.swo`
- **OS files**: `.DS_Store`, `Thumbs.db`, `ehthumbs.db`
- **Risc0 specific**: `*.bin`, `*.hex`, `proof_*.json`, `receipt_*.json`
- **Build outputs**: `*.wasm`, `*.so`, `*.dylib`, `*.dll`
- **Development artifacts**: `*.log`, `*.tmp`, `*.prof`, `*.bak`

### 2. `Cargo.toml` (Workspace Root)
**Purpose**: Defines the Rust workspace containing multiple related packages.

**Content**:
```toml
[workspace]
members = ["host", "methods"]
```

**Approach**: Uses Cargo workspaces to manage multiple related packages in a single repository, enabling shared dependencies and coordinated builds.

### 3. `host/` Directory

#### `host/Cargo.toml`
**Purpose**: Defines the host-side prover package configuration.

**Dependencies**:
- `anyhow = "1.0"` - Error handling
- `hex = "0.4"` - Hexadecimal encoding/decoding
- `methods = { path = "../methods" }` - Local methods package
- `risc0-zkvm = { version = "^3.0.3" }` - Risc0 ZKVM framework
- `serde = { version = "1.0", features = ["derive"] }` - Serialization
- `bincode = "1.3"` - Binary serialization

**Approach**: Minimal dependency set focused on ZKVM integration and serialization.

#### `host/src/lib.rs`
**Purpose**: Core prover implementation providing the main API for proof generation and verification.

**Key Components**:

1. **PublicInputs Struct**:
   ```rust
   pub struct PublicInputs {
       pub prev_root: String,      // Previous state root
       pub post_root: String,      // New state root
       pub receipts_root: String,  // Receipts Merkle root
       pub blob_hash: String,      // Blob data hash
       pub oracle_commit: String,  // Oracle commitment
   }
   ```

2. **ProveOutput Struct**:
   ```rust
   pub struct ProveOutput {
       pub receipt: Vec<u8>,  // Serialized proof receipt
       pub journal: Vec<u8>,  // Public outputs journal
   }
   ```

3. **Core Functions**:
   - `prove_block(inputs: &PublicInputs) -> Result<ProveOutput>`: Generates ZK proof
   - `verify_receipt(receipt_bytes: &[u8]) -> Result<()>`: Verifies ZK proof

**Technical Approach**:
- Uses Risc0's `default_prover()` for proof generation
- Serializes inputs using `ExecutorEnv::builder().write()`
- Generates proofs using `methods::GUEST_CODE_FOR_ZK_PROOF_ELF`
- Serializes receipts using `bincode` for efficient storage/transmission
- Provides verification using the guest code ID

### 4. `methods/` Directory

#### `methods/build.rs`
**Purpose**: Build script that embeds the guest code into the host binary.

**Content**:
```rust
fn main() {
    risc0_build::embed_methods();
}
```

**Approach**: Uses Risc0's build system to automatically embed compiled guest code as ELF binaries that can be executed within the ZKVM.

#### `methods/Cargo.toml`
**Purpose**: Configuration for the methods package that bridges host and guest code.

**Key Configuration**:
```toml
[package.metadata.risc0]
methods = ["guest"]
```

**Approach**: Defines the guest method to be embedded and compiled for ZKVM execution.

#### `methods/guest/` Directory

##### `methods/guest/Cargo.toml`
**Purpose**: Dependencies for the guest code that runs inside the ZKVM.

**Dependencies**:
- `risc0-zkvm = { version = "^3.0.3", default-features = false, features = ["std"] }`
- `serde = { version = "1.0", default-features = false, features = ["alloc", "derive"] }`

**Approach**: Minimal dependencies with `no_std` compatibility, using only `alloc` and `derive` features for memory management and serialization.

##### `methods/guest/src/main.rs`
**Purpose**: Guest program that executes inside the ZKVM to generate proofs.

**Key Features**:
1. **No Main Function**: Uses `#![no_main]` as it's called by the ZKVM runtime
2. **Entry Point**: `risc0_zkvm::guest::entry!(main)` defines the ZKVM entry point
3. **Public Inputs**: Same struct as host for data consistency
4. **Simple Logic**: Reads inputs and commits them as public outputs

**Technical Approach**:
- Uses `env::read()` to receive inputs from the host
- Uses `env::commit()` to publish public outputs
- Minimal computation to focus on proof generation rather than complex logic

#### `methods/src/lib.rs`
**Purpose**: Generated interface file that exposes the embedded guest code.

**Content**:
```rust
include!(concat!(env!("OUT_DIR"), "/methods.rs"));
```

**Approach**: Uses Rust's `include!` macro to include generated code from the build process, providing access to guest code ELF and ID constants.

## Technical Architecture

### Zero-Knowledge Proof Flow

1. **Input Preparation**: Host prepares `PublicInputs` with rollup state data
2. **Environment Setup**: Creates `ExecutorEnv` with serialized inputs
3. **Proof Generation**: Risc0 ZKVM executes guest code and generates proof
4. **Output Serialization**: Proof receipt and journal are serialized
5. **Verification**: Receipt can be verified using the guest code ID

### Key Technologies Used

1. **Risc0 ZKVM**: Zero-knowledge virtual machine for proof generation
2. **Rust**: Systems programming language with memory safety
3. **Serde**: Serialization framework for data exchange
4. **Bincode**: Binary serialization for efficient data transfer
5. **Cargo Workspaces**: Multi-package project management

### Security Considerations

1. **Cryptographic Proofs**: All computations are verified cryptographically
2. **Data Integrity**: State transitions are proven to be valid
3. **Privacy**: Sensitive computation details remain hidden
4. **Verifiability**: Anyone can verify proofs without trusting the prover

### Performance Characteristics

1. **Proof Generation**: Computationally intensive but produces compact proofs
2. **Verification**: Fast verification of generated proofs
3. **Serialization**: Efficient binary format for network transmission
4. **Memory Usage**: Optimized for minimal memory footprint in guest code

## Usage Example

```rust
use prover_host::{prove_block, verify_receipt, PublicInputs};

// Prepare inputs
let inputs = PublicInputs {
    prev_root: "0x123...".to_string(),
    post_root: "0x456...".to_string(),
    receipts_root: "0x789...".to_string(),
    blob_hash: "0xabc...".to_string(),
    oracle_commit: "0xdef...".to_string(),
};

// Generate proof
let proof = prove_block(&inputs)?;

// Verify proof
verify_receipt(&proof.receipt)?;
```

## Build Process

1. **Guest Compilation**: Guest code is compiled to RISC-V binary
2. **Method Embedding**: Build script embeds guest binary in host
3. **Host Compilation**: Host code is compiled with embedded guest
4. **Artifact Generation**: Final binary contains both host and guest code

This architecture provides a robust foundation for zero-knowledge proof generation in rollup systems, ensuring data integrity and computational correctness while maintaining privacy and verifiability.
