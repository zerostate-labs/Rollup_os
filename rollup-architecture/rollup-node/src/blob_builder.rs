use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use anyhow::Result;
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CelestiaBlob {
    pub namespace_id: String,        // 8-byte namespace ID
    pub data: Vec<u8>,              // Raw blob data
    pub share_version: u8,          // Share version
    pub commitment: String,         // Commitment hash
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlobMetadata {
    pub blob_id: String,
    pub block_numbers: Vec<u64>,
    pub transaction_count: usize,
    pub namespace_id: String,
    pub commitment: String,
    pub created_at: u64,
}

#[derive(Debug, Clone)]
pub struct BlobConfig {
    pub blocks_per_blob: usize,
    pub namespace_id: String,
    pub share_version: u8,
}

impl Default for BlobConfig {
    fn default() -> Self {
        Self {
            blocks_per_blob: 2,
            namespace_id: "0000000000000000".to_string(),
            share_version: 0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlockData {
    pub block_number: u64,
    pub transactions: Vec<String>,
    pub timestamp: u64,
}

pub struct BlobBuilder {
    pub config: BlobConfig,  // Made public to allow configuration
    blocks: HashMap<u64, BlockData>,
    blob_counter: u64,
}

impl BlobBuilder {
    pub fn new(config: BlobConfig) -> Self {
        Self {
            config,
            blocks: HashMap::new(),
            blob_counter: 0,
        }
    }

    /// Add a block with its transactions to the builder
    pub fn add_block(&mut self, block_number: u64, transactions: Vec<String>, timestamp: u64) {
        self.blocks.insert(block_number, BlockData {
            block_number,
            transactions,
            timestamp,
        });
    }

    /// Create blobs from existing blocks
    pub fn create_blobs_from_blocks(&mut self) -> Result<Vec<(CelestiaBlob, BlobMetadata)>> {
        let mut blobs = Vec::new();
        
        // Get all block numbers and sort them
        let mut block_numbers: Vec<u64> = self.blocks.keys().cloned().collect();
        block_numbers.sort();
        
        // Create blobs by grouping blocks
        let mut current_blob_blocks = Vec::new();
        let mut current_transactions = Vec::new();
        
        for &block_num in &block_numbers {
            if let Some(block_data) = self.blocks.get(&block_num) {
                current_blob_blocks.push(block_num);
                current_transactions.extend(block_data.transactions.clone());
                
                // Create a blob when we have enough blocks
                if current_blob_blocks.len() >= self.config.blocks_per_blob {
                    let (blob, metadata) = self.create_blob_from_blocks(
                        current_blob_blocks.clone(),
                        current_transactions.clone()
                    )?;
                    blobs.push((blob, metadata));
                    
                    // Reset for next blob
                    current_blob_blocks.clear();
                    current_transactions.clear();
                }
            }
        }
        
        // Create final blob with remaining blocks (if any)
        if !current_blob_blocks.is_empty() {
            let (blob, metadata) = self.create_blob_from_blocks(
                current_blob_blocks,
                current_transactions
            )?;
            blobs.push((blob, metadata));
        }
        
        Ok(blobs)
    }

    /// Create a single blob from a group of blocks
    fn create_blob_from_blocks(&mut self, block_numbers: Vec<u64>, transactions: Vec<String>) -> Result<(CelestiaBlob, BlobMetadata)> {
        // Create blob data
        let blob_data = self.serialize_blob_data(&block_numbers, &transactions)?;
        
        // Calculate commitment (hash of the data)
        let commitment = self.calculate_commitment(&blob_data);
        
        // Create Celestia blob
        let celestia_blob = CelestiaBlob {
            namespace_id: self.config.namespace_id.clone(),
            data: blob_data,
            share_version: self.config.share_version,
            commitment: commitment.clone(),
        };

        // Create metadata
        let metadata = BlobMetadata {
            blob_id: format!("blob_{:06}", self.blob_counter),
            block_numbers,
            transaction_count: transactions.len(),
            namespace_id: self.config.namespace_id.clone(),
            commitment,
            created_at: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)?
                .as_secs(),
        };

        self.blob_counter += 1;
        
        Ok((celestia_blob, metadata))
    }

    /// Serialize block and transaction data for the blob
    fn serialize_blob_data(&self, block_numbers: &[u64], transactions: &[String]) -> Result<Vec<u8>> {
        let blob_content = serde_json::json!({
            "version": "2.0",
            "blocks_per_blob": self.config.blocks_per_blob,
            "block_numbers": block_numbers,
            "transactions": transactions,
            "total_transactions": transactions.len(),
            "created_at": std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)?
                .as_secs(),
        });
        
        Ok(serde_json::to_vec(&blob_content)?)
    }

    /// Calculate commitment hash for the blob data
    fn calculate_commitment(&self, data: &[u8]) -> String {
        let mut hasher = Sha256::new();
        hasher.update(data);
        hex::encode(hasher.finalize())
    }

    /// Get number of stored blocks
    pub fn block_count(&self) -> usize {
        self.blocks.len()
    }

    /// Get total transaction count across all blocks
    pub fn total_transaction_count(&self) -> usize {
        self.blocks.values().map(|block| block.transactions.len()).sum()
    }

    /// Clear all stored blocks
    pub fn clear(&mut self) {
        self.blocks.clear();
    }

    /// Get list of stored block numbers
    pub fn get_block_numbers(&self) -> Vec<u64> {
        self.blocks.keys().cloned().collect()
    }
}

/// Utility functions for blob management
pub mod utils {
    use super::*;
    use std::fs;
    use std::path::Path;

    /// Save blob to local storage
    pub fn save_blob<P: AsRef<Path>>(
        dir: P, 
        blob: &CelestiaBlob, 
        metadata: &BlobMetadata
    ) -> Result<String> {
        let blob_dir = dir.as_ref().join("blobs");
        fs::create_dir_all(&blob_dir)?;

        // Save blob data
        let blob_path = blob_dir.join(format!("{}.blob", metadata.blob_id));
        fs::write(&blob_path, &blob.data)?;

        // Save metadata
        let metadata_path = blob_dir.join(format!("{}.json", metadata.blob_id));
        let metadata_json = serde_json::to_string_pretty(metadata)?;
        fs::write(metadata_path, metadata_json)?;

        Ok(blob_path.to_string_lossy().to_string())
    }

    /// Load blob from local storage
    pub fn load_blob<P: AsRef<Path>>(dir: P, blob_id: &str) -> Result<(CelestiaBlob, BlobMetadata)> {
        let blob_dir = dir.as_ref().join("blobs");
        
        // Load metadata
        let metadata_path = blob_dir.join(format!("{}.json", blob_id));
        let metadata_json = fs::read_to_string(metadata_path)?;
        let metadata: BlobMetadata = serde_json::from_str(&metadata_json)?;

        // Load blob data
        let blob_path = blob_dir.join(format!("{}.blob", blob_id));
        let data = fs::read(blob_path)?;

        let blob = CelestiaBlob {
            namespace_id: metadata.namespace_id.clone(),
            data,
            share_version: 0,
            commitment: metadata.commitment.clone(),
        };

        Ok((blob, metadata))
    }

    /// Load block data from local storage
    pub fn load_block<P: AsRef<Path>>(dir: P, block_number: u64) -> Result<BlockData> {
        let block_path = dir.as_ref().join(format!("block_{:06}.json", block_number));
        let block_json = fs::read_to_string(block_path)?;
        
        #[derive(Deserialize)]
        struct BlockFile {
            transactions: Vec<String>,
            header: serde_json::Value,
        }
        
        let block_file: BlockFile = serde_json::from_str(&block_json)?;
        let timestamp = block_file.header["timestamp"].as_u64().unwrap_or(0);
        
        Ok(BlockData {
            block_number,
            transactions: block_file.transactions,
            timestamp,
        })
    }
}
