use anyhow::{Result, anyhow};
use serde::{Deserialize, Serialize};
use std::process::Command;
use std::time::Duration;
use tokio::time::sleep;

/// Configuration for Celestia integration
#[derive(Debug, Clone)]
pub struct CelestiaConfig {
    pub node_url: String,
    pub chain_id: String,
    pub wallet_name: String,
    pub namespace_id: String,
    pub gas_fees: String,
    pub rpc_url: String,
}

impl Default for CelestiaConfig {
    fn default() -> Self {
        Self {
            node_url: "https://rpc-mocha.pops.one:443".to_string(),
            chain_id: "mocha-4".to_string(),
            wallet_name: "validator".to_string(),
            namespace_id: "7a65726f7374617465ab".to_string(), // "zerostate" + padding (10 bytes)
            gas_fees: "500utia".to_string(),
            rpc_url: "https://rpc-mocha.pops.one:443".to_string(),
        }
    }
}

/// Response from Celestia blob submission
#[derive(Debug, Deserialize)]
pub struct CelestiaResponse {
    pub code: u32,
    pub txhash: Option<String>,
    pub raw_log: Option<String>,
}

/// Celestia client for submitting blobs
pub struct CelestiaClient {
    config: CelestiaConfig,
}

impl CelestiaClient {
    pub fn new(config: CelestiaConfig) -> Self {
        Self { config }
    }

    /// Submit a single blob to Celestia
    pub async fn submit_blob(&self, data: &[u8]) -> Result<String> {
        let hex_data = format!("0x{}", hex::encode(data));
        
        let output = Command::new("celestia-appd")
            .args(&[
                "tx", "blob", "PayForBlob",
                &self.config.namespace_id,
                &hex_data,
                "--from", &self.config.wallet_name,
                "--chain-id", &self.config.chain_id,
                "--node", &self.config.rpc_url,
                "--gas", "auto",
                "--fees", &self.config.gas_fees,
                "-y"
            ])
            .output()?;

        let stdout = String::from_utf8_lossy(&output.stdout);
        let stderr = String::from_utf8_lossy(&output.stderr);

        if !output.status.success() {
            return Err(anyhow!("Failed to submit blob: {}\nStderr: {}", stdout, stderr));
        }

        // Parse the transaction hash from output
        if let Some(tx_hash) = self.extract_tx_hash(&stdout) {
            Ok(tx_hash)
        } else {
            Err(anyhow!("Could not extract transaction hash from output: {}", stdout))
        }
    }

    /// Submit multiple blobs with rate limiting
    pub async fn submit_blobs_bulk(&self, blobs: Vec<Vec<u8>>, delay_ms: u64) -> Result<Vec<String>> {
        let mut tx_hashes = Vec::new();
        
        for (i, blob_data) in blobs.iter().enumerate() {
            println!("Submitting blob {}/{}", i + 1, blobs.len());
            
            match self.submit_blob(blob_data).await {
                Ok(tx_hash) => {
                    println!("✅ Blob {} submitted successfully: {}", i + 1, tx_hash);
                    tx_hashes.push(tx_hash);
                }
                Err(e) => {
                    println!("❌ Failed to submit blob {}: {}", i + 1, e);
                    // Continue with other blobs even if one fails
                }
            }
            
            // Rate limiting delay
            if i < blobs.len() - 1 {
                sleep(Duration::from_millis(delay_ms)).await;
            }
        }
        
        Ok(tx_hashes)
    }

    /// Check wallet balance
    pub async fn check_balance(&self) -> Result<String> {
        let output = Command::new("celestia-appd")
            .args(&[
                "query", "bank", "balances",
                &self.get_wallet_address()?,
                "--node", &self.config.rpc_url
            ])
            .output()?;

        let stdout = String::from_utf8_lossy(&output.stdout);
        
        if !output.status.success() {
            return Err(anyhow!("Failed to check balance: {}", stdout));
        }
        
        Ok(stdout.to_string())
    }

    /// Get wallet address
    pub fn get_wallet_address(&self) -> Result<String> {
        let output = Command::new("celestia-appd")
            .args(&["keys", "show", &self.config.wallet_name, "-a"])
            .output()?;

        let stdout = String::from_utf8_lossy(&output.stdout);
        
        if !output.status.success() {
            return Err(anyhow!("Failed to get wallet address: {}", stdout));
        }
        
        Ok(stdout.trim().to_string())
    }

    /// Verify blob was submitted by checking transaction
    pub async fn verify_blob(&self, tx_hash: &str) -> Result<bool> {
        let output = Command::new("celestia-appd")
            .args(&[
                "query", "tx", tx_hash,
                "--node", &self.config.rpc_url
            ])
            .output()?;

        let stdout = String::from_utf8_lossy(&output.stdout);
        
        // If the command succeeds, the transaction exists
        Ok(output.status.success())
    }

    /// Extract transaction hash from celestia-appd output
    fn extract_tx_hash(&self, output: &str) -> Option<String> {
        // Look for patterns like "txhash: ABC123..." or "tx: ABC123..."
        for line in output.lines() {
            if line.contains("txhash:") {
                if let Some(hash) = line.split("txhash:").nth(1) {
                    return Some(hash.trim().to_string());
                }
            }
            if line.contains("tx:") && line.contains("0x") {
                if let Some(hash) = line.split("tx:").nth(1) {
                    return Some(hash.trim().to_string());
                }
            }
        }
        None
    }
}

/// Utility functions for Celestia integration
pub mod utils {
    use super::*;
    use std::fs;
    use std::path::Path;

    /// Save blob data to temporary file for Celestia submission
    pub fn prepare_blob_data(blob_data: &[u8]) -> Result<Vec<u8>> {
        // For now, just return the data as-is
        // In the future, we might want to compress or format it differently
        Ok(blob_data.to_vec())
    }

    /// Create a test blob with random data
    pub fn create_test_blob(size_bytes: usize) -> Vec<u8> {
        use std::collections::hash_map::DefaultHasher;
        use std::hash::{Hash, Hasher};
        
        let mut data = Vec::with_capacity(size_bytes);
        let mut hasher = DefaultHasher::new();
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();
        
        hasher.write_u64(timestamp);
        
        for i in 0..size_bytes {
            hasher.write_u8(i as u8);
            data.push((hasher.finish() & 0xFF) as u8);
        }
        
        data
    }

    /// Generate random namespace ID
    pub fn generate_namespace_id() -> String {
        use std::collections::hash_map::DefaultHasher;
        use std::hash::{Hash, Hasher};
        
        let mut hasher = DefaultHasher::new();
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();
        
        hasher.write_u64(timestamp);
        format!("{:08x}", hasher.finish())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_namespace_generation() {
        let ns1 = utils::generate_namespace_id();
        let ns2 = utils::generate_namespace_id();
        
        assert_eq!(ns1.len(), 8);
        assert_eq!(ns2.len(), 8);
        assert_ne!(ns1, ns2); // Should be different
    }

    #[test]
    fn test_test_blob_creation() {
        let blob = utils::create_test_blob(100);
        assert_eq!(blob.len(), 100);
    }
}
