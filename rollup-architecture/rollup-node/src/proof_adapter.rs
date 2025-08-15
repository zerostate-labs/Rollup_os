use sha2::{Digest, Sha256};

pub fn generate_mock_proof(
    prev_root: &str,
    post_root: &str,
    blob_hash: &str,
    oracle_commit: &str,
) -> Vec<u8> {
    let mut hasher = Sha256::new();
    hasher.update(prev_root.as_bytes());
    hasher.update(post_root.as_bytes());
    hasher.update(blob_hash.as_bytes());
    hasher.update(oracle_commit.as_bytes());
    hasher.update(b"mock_proof_v1"); // Version identifier
    
    let result = hasher.finalize();
    result.to_vec()
}

pub fn verify_mock_proof(
    proof: &[u8],
    prev_root: &str,
    post_root: &str,
    blob_hash: &str,
    oracle_commit: &str,
) -> bool {
    let expected_proof = generate_mock_proof(prev_root, post_root, blob_hash, oracle_commit);
    proof == expected_proof
}
