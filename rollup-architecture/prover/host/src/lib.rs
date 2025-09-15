use anyhow::Result;
use risc0_zkvm::{default_prover, ExecutorEnv, Receipt};

#[derive(Debug, serde::Serialize, serde::Deserialize, Clone)]
pub struct PublicInputs {
    pub prev_root: String,
    pub post_root: String,
    pub receipts_root: String,
    pub blob_hash: String,
    pub oracle_commit: String,
}

#[derive(Debug, serde::Serialize, serde::Deserialize, Clone)]
pub struct ProveOutput {
    pub receipt: Vec<u8>,
    pub journal: Vec<u8>,
}

pub fn prove_block(inputs: &PublicInputs) -> Result<ProveOutput> {
    let env = ExecutorEnv::builder().write(inputs)?.build()?;

    let prover = default_prover();
    let prove_info = prover.prove(env, methods::GUEST_CODE_FOR_ZK_PROOF_ELF)?;
    let receipt: Receipt = prove_info.receipt;

    let journal_bytes = receipt.journal.bytes.clone();
    let receipt_bytes = bincode::serialize(&receipt)?;

    Ok(ProveOutput {
        receipt: receipt_bytes,
        journal: journal_bytes,
    })
}

pub fn verify_receipt(receipt_bytes: &[u8]) -> Result<()> {
    let receipt: Receipt = bincode::deserialize(receipt_bytes)?;
    receipt.verify(methods::GUEST_CODE_FOR_ZK_PROOF_ID)?;
    Ok(())
}


