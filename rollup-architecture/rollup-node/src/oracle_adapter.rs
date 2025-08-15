use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OracleData {
    pub timestamp: u64,
    pub price: String,
    pub source: String,
    pub signature: String, // Mock signature
}

impl OracleData {
    pub fn new(price: &str, source: &str) -> Self {
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
        
        Self {
            timestamp,
            price: price.to_string(),
            source: source.to_string(),
            signature: format!("mock_sig_{}", timestamp), // Mock signature
        }
    }
}

pub fn current_oracle_commit() -> String {
    // return a mock oracle commitment
    let oracle_data = OracleData::new("50000", "mock_pyth");
    
    // Create a commitment hash
    let mut hasher = Sha256::new();
    hasher.update(oracle_data.timestamp.to_string().as_bytes());
    hasher.update(oracle_data.price.as_bytes());
    hasher.update(oracle_data.source.as_bytes());
    hasher.update(oracle_data.signature.as_bytes());
    
    let result = hasher.finalize();
    hex::encode(result)
}

pub fn get_oracle_data() -> OracleData {
    OracleData::new("50000", "mock_pyth")
}
