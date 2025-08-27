#![no_main]
risc0_zkvm_guest::entry!(main);

use rollup_shared_types::Witness;
use rollup_core_state::CoreState;

pub fn main() {
    let witness_bytes: Vec<u8> = risc0_zkvm_guest::env::read();
    let witness: Witness = bincode::deserialize(&witness_bytes)
        .expect("Failed to deserialize witness");

    let mut state = CoreState::new();
    state.credit("alice", 1_000_000);
    state.credit("bob", 1000);
    state.credit("charlie", 500_000);
    state.credit("diana", 750_000);

    let computed_prior_root = state.compute_state_root(witness.block_number - 1);
    if computed_prior_root != witness.prior_state_root {
        panic!("Prior state root mismatch");
    }
    state.set_last_root(witness.prior_state_root);

    let public_outputs = state.execute_block(&witness)
        .expect("Failed to execute block");

    let computed_tx_root = CoreState::compute_tx_root(&witness.transactions);
    if computed_tx_root != witness.tx_root {
        panic!("Transaction root mismatch");
    }

    let journal_bytes = bincode::serialize(&public_outputs)
        .expect("Failed to serialize public outputs");
    risc0_zkvm_guest::env::commit(&journal_bytes);
}


