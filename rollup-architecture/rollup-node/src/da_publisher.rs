use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::Path;

/// Blob data structure that we post to DA
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Blob {
    pub block_number: u64,
    pub txs: Vec<String>,       // flattened tx list for simplicity
    pub oracle_commit: String,  // commit string from Oracle input layer
    pub state_root: String,     // post-state root for this block
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
    let filename = format!("block_{:06}.json", blob.block_number);
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
