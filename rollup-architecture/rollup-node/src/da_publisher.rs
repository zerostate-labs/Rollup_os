use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::Path;

/// Block header
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlockHeader {
    pub parent_hash: String,         // H256 as hex string for now
    pub block_number: u64,
    pub timestamp: u64,
    pub proposer: String,           // Address as hex string
    pub state_root: String,         // H256 as hex string
    pub txs_root: String,           // H256 as hex string
    pub receipts_root: String,      // H256 as hex string
    pub da_pointer: String,         // BlobCommitment placeholder
    pub l1_finality_pointer: String, // L1Commitment placeholder
}

/// Execution results from state transition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecutionResult {
    pub state_root: String,
    pub receipts_root: String,
    pub gas_used: u64,
}

/// Main block structure that we post to DA
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Blob {
    pub header: BlockHeader,
    pub transactions: Vec<String>,    // flattened tx list for simplicity
    pub execution_payload: ExecutionResult,
    pub oracle_commit: String,
    pub proofs: Option<String>,
}

/// Ensure that the given directory exists
pub fn ensure_dir<P: AsRef<Path>>(dir: P) -> anyhow::Result<()> {
    if !dir.as_ref().exists() {
        fs::create_dir_all(&dir)?;
    }
    Ok(())
}

/// Write blob to DA (Phase 0: local file), return (path, hash)
pub fn write_blob<P: AsRef<Path>>(dir: P, blob: &Blob) -> anyhow::Result<(String, String)> {
    let json_data = serde_json::to_vec_pretty(&blob)?;
    let hash = hash_bytes(&json_data);
    let filename = format!("block_{:06}.json", blob.header.block_number);
    let full_path = dir.as_ref().join(filename);

    fs::write(&full_path, &json_data)?;

    Ok((
        full_path.to_string_lossy().to_string(),
        hash,
    ))
}

/// Hash helper: SHA256 -> hex
fn hash_bytes(data: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data);
    let result = hasher.finalize();
    hex::encode(result)
}

// --- Future Celestia integration sketch ---
//
// #[cfg(feature = "celestia")]
// pub async fn submit_to_celestia(blob: &Blob, celestia_node_url: &str, auth_token: &str) -> anyhow::Result<String> {
//     // 1. Serialize blob to bytes
//     let json_data = serde_json::to_vec(blob)?;
//     // 2. POST to Celestia light node API: /submit_pfd
//     // 3. Return commitment/hash
//     todo!("Integrate with Celestia RPC");
// }
