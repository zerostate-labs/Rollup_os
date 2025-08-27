use risc0_zkvm::{default_prover, ExecutorEnv, Receipt};
use rollup_methods::{ROLLUP_GUEST_ELF, ROLLUP_METHOD_ID};
use rollup_shared_types::{Witness, PublicOutputs, Transaction, OracleEntry};
use rollup_core_state::CoreState;
use std::fs;
use sha2::{Digest, Sha256};

fn main() -> anyhow::Result<()> {
    // Example: Create a witness for block 1
    let witness = create_example_witness()?;
    
    // Validate the witness locally first
    validate_witness_locally(&witness)?;

    // Build executor environment
    let env = ExecutorEnv::builder()
        .write(&bincode::serialize(&witness)?)
        .unwrap()
        .build()
        .unwrap();

    // Run the prover
    let prover = default_prover();
    let session = prover.prove(env, ROLLUP_GUEST_ELF)?;

    // Extract and validate the receipt
    let receipt = session.receipt;
    
    // Verify the receipt locally before publishing
    verify_receipt_locally(&receipt)?;

    // Extract journal output
    let journal: Vec<u8> = receipt.journal.decode()?;
    let public_outputs: PublicOutputs = bincode::deserialize(&journal)?;

    println!("Block {}: {} -> {}", 
        public_outputs.block_number,
        hex::encode(public_outputs.prior_state_root),
        hex::encode(public_outputs.post_state_root)
    );

    // Save proof artifacts
    save_proof_artifacts(&receipt, &public_outputs, &witness)?;

    Ok(())
}

fn create_example_witness() -> anyhow::Result<Witness> {
    // Create some example transactions
    let transactions = vec![
        Transaction {
            from: "alice".to_string(),
            to: "bob".to_string(),
            amount: "100".to_string(),
            nonce: 0,
        },
        Transaction {
            from: "charlie".to_string(),
            to: "diana".to_string(),
            amount: "50".to_string(),
            nonce: 0,
        },
    ];

    // Create example oracle data
    let oracle_data = vec![
        OracleEntry {
            source: "pyth".to_string(),
            price: "50000".to_string(),
            timestamp: 1234567890,
            signature: "example_signature".to_string(),
        },
    ];

    // Compute transaction root
    let tx_root = CoreState::compute_tx_root(&transactions);
    
    // Compute oracle root (simplified)
    let mut oracle_hasher = Sha256::new();
    for oracle in &oracle_data {
        oracle_hasher.update(oracle.source.as_bytes());
        oracle_hasher.update(oracle.price.as_bytes());
        oracle_hasher.update(oracle.timestamp.to_string().as_bytes());
    }
    let oracle_root: [u8; 32] = oracle_hasher.finalize().into();

    // Create a mock blob root
    let blob_root = [1u8; 32]; // In production, this would come from Celestia

    // Initialize state to get prior state root
    let mut state = CoreState::new();
    state.credit("alice", 1_000_000);
    state.credit("bob", 1000);
    state.credit("charlie", 500_000);
    state.credit("diana", 750_000);
    
    let prior_state_root = state.compute_state_root(0); // Block 0

    Ok(Witness {
        program_version: 1,
        prior_state_root,
        block_number: 1,
        timestamp: 1234567890,
        tx_root,
        oracle_root,
        blob_root,
        transactions,
        oracle_data,
    })
}

fn validate_witness_locally(witness: &Witness) -> anyhow::Result<()> {
    // Replay the execution locally to verify it's valid
    let mut state = CoreState::new();
    state.credit("alice", 1_000_000);
    state.credit("bob", 1000);
    state.credit("charlie", 500_000);
    state.credit("diana", 750_000);
    
    let computed_prior_root = state.compute_state_root(0);
    if computed_prior_root != witness.prior_state_root {
        return Err(anyhow::anyhow!("Prior state root mismatch"));
    }
    state.last_root = witness.prior_state_root;

    let expected_outputs = state.execute_block(witness)?;
    println!("Local validation successful: {} -> {}", 
        hex::encode(expected_outputs.prior_state_root),
        hex::encode(expected_outputs.post_state_root)
    );

    Ok(())
}

fn verify_receipt_locally(receipt: &Receipt) -> anyhow::Result<()> {
    // Verify the receipt against the METHOD_ID
    receipt.verify(ROLLUP_METHOD_ID)?;
    println!("Receipt verification successful");
    Ok(())
}

fn save_proof_artifacts(
    receipt: &Receipt, 
    public_outputs: &PublicOutputs, 
    witness: &Witness
) -> anyhow::Result<()> {
    // Save the receipt (proof)
    fs::write("proof.bin", bincode::serialize(receipt)?)?;
    
    // Save the journal (public outputs)
    fs::write("journal.bin", bincode::serialize(public_outputs)?)?;
    
    // Save metadata
    let metadata = serde_json::json!({
        "block_number": public_outputs.block_number,
        "method_id": hex::encode(ROLLUP_METHOD_ID),
        "program_version": public_outputs.program_version,
        "prior_state_root": hex::encode(public_outputs.prior_state_root),
        "post_state_root": hex::encode(public_outputs.post_state_root),
        "blob_root": hex::encode(public_outputs.blob_root),
        "timestamp": witness.timestamp,
    });
    fs::write("metadata.json", serde_json::to_string_pretty(&metadata)?)?;
    
    println!("Proof artifacts saved:");
    println!("  - proof.bin (receipt)");
    println!("  - journal.bin (public outputs)");
    println!("  - metadata.json");
    
    Ok(())
}
