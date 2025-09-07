#![no_main]
use risc0_zkvm::guest::env;

risc0_zkvm::guest::entry!(main);

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct PublicInputs {
    pub prev_root: String,
    pub post_root: String,
    pub blob_hash: String,
    pub oracle_commit: String,
}

fn main() {
    let inputs: PublicInputs = env::read();
    env::commit(&inputs);
}


