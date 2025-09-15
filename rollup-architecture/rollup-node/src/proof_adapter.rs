#[cfg(feature = "mock-proof")]
use sha2::{Digest, Sha256};

#[cfg(feature = "mock-proof")]
pub fn generate_proof(
    prev_root: &str,
    post_root: &str,
    receipts_root: &str,
    blob_hash: &str,
    oracle_commit: &str,
) -> Vec<u8> {
    let mut hasher = Sha256::new();
    hasher.update(prev_root.as_bytes());
    hasher.update(post_root.as_bytes());
    hasher.update(receipts_root.as_bytes());
    hasher.update(blob_hash.as_bytes());
    hasher.update(oracle_commit.as_bytes());
    hasher.update(b"mock_proof_v2");
    hasher.finalize().to_vec()
}

#[cfg(feature = "mock-proof")]
pub fn verify_proof(
    proof: &[u8],
    prev_root: &str,
    post_root: &str,
    receipts_root: &str,
    blob_hash: &str,
    oracle_commit: &str,
) -> bool {
    let expected_proof = generate_proof(prev_root, post_root, receipts_root, blob_hash, oracle_commit);
    proof == expected_proof
}

#[cfg(not(feature = "mock-proof"))]
pub fn generate_proof(
    prev_root: &str,
    post_root: &str,
    receipts_root: &str,
    blob_hash: &str,
    oracle_commit: &str,
) -> Vec<u8> {
    let inputs = prover_host::PublicInputs {
        prev_root: prev_root.to_string(),
        post_root: post_root.to_string(),
        receipts_root: receipts_root.to_string(),
        blob_hash: blob_hash.to_string(),
        oracle_commit: oracle_commit.to_string(),
    };
    let out = prover_host::prove_block(&inputs).expect("prover failed");
    out.receipt
}

#[cfg(not(feature = "mock-proof"))]
pub fn verify_proof(proof_bytes: &[u8]) -> bool {
    prover_host::verify_receipt(proof_bytes).is_ok()
}

pub fn verify_proof_unified(
    proof: &[u8],
    prev_root: &str,
    post_root: &str,
    receipts_root: &str,
    blob_hash: &str,
    oracle_commit: &str,
) -> bool {
    #[cfg(feature = "mock-proof")]
    {
        return verify_proof(proof, prev_root, post_root, receipts_root, blob_hash, oracle_commit);
    }
    #[cfg(not(feature = "mock-proof"))]
    {
        return verify_proof(proof);
    }
}
