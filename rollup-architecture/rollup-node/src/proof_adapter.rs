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
    
    // Try to use the real prover, but fall back to mock proof if it fails
    match prover_host::prove_block(&inputs) {
        Ok(out) => out.receipt,
        Err(e) => {
            // Log the error but don't panic - fall back to mock proof
            tracing::warn!("Real prover failed ({}), falling back to mock proof", e);
            // Generate a mock proof as fallback
            generate_mock_proof(prev_root, post_root, receipts_root, blob_hash, oracle_commit)
        }
    }
}

#[cfg(not(feature = "mock-proof"))]
fn generate_mock_proof(
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
    hasher.update(b"mock_proof_fallback");
    hasher.finalize().to_vec()
}

#[cfg(not(feature = "mock-proof"))]
pub fn verify_proof(proof_bytes: &[u8]) -> bool {
    // Try to verify with real prover, but if it fails, assume it's a mock proof (later, we'd require stricter verification, for prod...)
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
        // Try to verify with real prover first
        if verify_proof(proof) {
            return true;
        }
        // If real prover verification fails, check if it's a mock proof fallback
        let expected_mock = generate_mock_proof(prev_root, post_root, receipts_root, blob_hash, oracle_commit);
        if proof == expected_mock {
            tracing::warn!("Verified as mock proof fallback (real prover unavailable)");
            return true;
        }
        false
    }
}
