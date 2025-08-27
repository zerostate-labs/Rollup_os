# Rollup Prover Implementation

This directory contains the complete ZK prover implementation for the Rollup_OS system using RISC Zero.

## Architecture Overview

The prover consists of several components that work together to generate ZK proofs of rollup state transitions:

```
prover/
├── guest/           # RISC Zero guest program (runs in zkVM)
├── host/            # Host program (orchestrates proving)
├── methods/         # Build system for guest ELF and METHOD_ID
├── shared-types/    # Common data structures
├── core-state/      # Deterministic state machine logic
└── verifier/        # Ethereum smart contract verifier
```

## How It Works

1. **Rollup Node** executes transactions and publishes DA blobs to Celestia
2. **Prover Host** reads DA blobs and constructs a `Witness` with:
   - Prior state root (S)
   - Block number and timestamp
   - Transaction list and transaction root
   - Oracle data and oracle root
   - Celestia blob root
3. **Prover Guest** (in zkVM) reads the witness and:
   - Replays the state machine execution deterministically
   - Computes the new state root (S')
   - Commits `PublicOutputs` to the journal
4. **Host** extracts the proof (receipt) and journal
5. **Verifier Contract** (on Ethereum) verifies the proof and updates state

## Key Components

### Guest Program (`guest/src/main.rs`)
- Runs inside RISC Zero's zkVM
- Reads `Witness` data from host
- Executes the same state machine logic as the rollup node
- Commits `PublicOutputs` to the journal
- Must be deterministic and `no_std` compatible

### Host Program (`host/src/main.rs`)
- Orchestrates the proving process
- Constructs `Witness` from DA and rollup metadata
- Runs the guest program and extracts proof
- Validates proof locally before publishing
- Saves proof artifacts (receipt, journal, metadata)

### Core State Machine (`core-state/src/lib.rs`)
- Shared between rollup node and prover guest
- Implements deterministic state transitions
- Feature-gated for `std` (rollup node) vs `no_std` (guest)
- Handles account balances, nonces, and state root computation

### Verifier Contract (`verifier/SettlementVerifier.sol`)
- Ethereum smart contract for on-chain verification
- Verifies RISC Zero proofs against fixed `METHOD_ID`
- Checks blob commitment via Blobstream
- Updates canonical state roots
- Emits events for bridge consumers

## Data Structures

### Witness (Input to Guest)
```rust
pub struct Witness {
    pub program_version: u32,
    pub prior_state_root: [u8; 32],    // S
    pub block_number: u64,
    pub timestamp: u64,
    pub tx_root: [u8; 32],             // Merkle root of transactions
    pub oracle_root: [u8; 32],         // Root of oracle data
    pub blob_root: [u8; 32],           // Celestia blob root
    pub transactions: Vec<Transaction>, // Full transaction list
    pub oracle_data: Vec<OracleEntry>, // Full oracle data
}
```

### PublicOutputs (Output from Guest)
```rust
pub struct PublicOutputs {
    pub program_version: u32,
    pub prior_state_root: [u8; 32],    // Echo S for verification
    pub post_state_root: [u8; 32],     // S'
    pub block_number: u64,
    pub tx_root: [u8; 32],
    pub oracle_root: [u8; 32],
    pub blob_root: [u8; 32],
}
```

## Building and Testing

### Prerequisites
- Rust toolchain
- Node.js and npm
- RISC Zero toolchain

### Build the Prover
```bash
cd prover
cargo build --workspace
```

### Run the Host Prover
```bash
cd host
cargo run
```

This will:
1. Create an example witness
2. Validate it locally
3. Generate a ZK proof
4. Save proof artifacts to files

### Test the Verifier
```bash
cd verifier
npm install
npx hardhat compile
```

## Proof Artifacts

The host generates three files per proof:

- `proof.bin` - The RISC Zero receipt (the actual proof)
- `journal.bin` - The public outputs (serialized)
- `metadata.json` - Human-readable metadata

## Integration with Rollup Node

The prover is designed to work with the existing rollup node:

1. **State Machine Compatibility**: The `core-state` crate uses the same logic as the rollup node's state machine
2. **Data Format**: Witness construction matches the rollup node's blob format
3. **State Roots**: Uses the same state root computation as the rollup node

## Security Considerations

### Trust Assumptions
- **ZK Proofs**: Correctness relies on RISC Zero's soundness
- **Data Availability**: Depends on Celestia's availability sampling
- **Blobstream**: Requires honest relay of blob roots to Ethereum
- **Oracle Data**: Assumes oracle signatures are valid

### Security Features
- **Method Binding**: Verifier only accepts proofs from the correct guest program
- **State Continuity**: Enforces sequential block numbers and state root chaining
- **DA Verification**: Checks blob commitment before accepting proofs
- **Version Control**: Program version prevents stale proof acceptance

## Production Considerations

### Performance Optimizations
- **Batching**: Prove multiple blocks per proof to amortize costs
- **Recursive Aggregation**: Use recursive SNARKs to compress multiple proofs
- **Parallel Proving**: Run multiple provers in parallel
- **State Compression**: Use Merkle trees for efficient state representation

### Scalability Improvements
- **Merkle Roots**: Switch from full transaction lists to Merkle roots
- **Oracle Aggregation**: Use threshold signatures for oracle data
- **Blobstream Integration**: Connect to real Blobstream for DA verification
- **State Reconstruction**: Implement efficient state reconstruction in guest

### Monitoring and Observability
- **Proof Metrics**: Track proving time, success rate, gas costs
- **State Tracking**: Monitor state root updates and finality
- **Blobstream Health**: Monitor blob commitment delays
- **Oracle Reliability**: Track oracle data freshness and accuracy

## Next Steps

1. **Deploy to Testnet**: Deploy the verifier contract and test end-to-end
2. **Blobstream Integration**: Connect to real Blobstream for DA verification
3. **State Reconstruction**: Implement proper state reconstruction in guest
4. **Oracle Integration**: Add real oracle signature verification
5. **Performance Optimization**: Implement batching and recursive aggregation
6. **Monitoring**: Add comprehensive monitoring and alerting
7. **Security Audit**: Conduct formal security audit of the implementation

## Troubleshooting

### Common Issues

**Build Errors**
- Ensure RISC Zero toolchain is properly installed
- Check that all dependencies are compatible versions

**Proof Generation Fails**
- Verify witness data is valid and consistent
- Check that state machine logic matches rollup node
- Ensure deterministic execution (no random numbers, timestamps, etc.)

**Verification Fails**
- Verify `METHOD_ID` matches between host and verifier
- Check that blob is committed in Blobstream
- Ensure journal format matches verifier expectations

### Debugging Tips

1. **Local Validation**: Always validate witnesses locally before proving
2. **State Comparison**: Compare state roots between rollup node and prover
3. **Logging**: Add detailed logging to track execution flow
4. **Small Tests**: Start with simple transactions and gradually increase complexity
