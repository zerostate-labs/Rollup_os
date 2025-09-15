use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;

/// Transaction execution status
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum TxStatus {
    Success,
    Revert(String), // Revert reason
    InvalidNonce,
    InsufficientBalance,
    InvalidAmount,
    InvalidOpcode,
    GasLimitExceeded,
    Other(String),
}

impl TxStatus {
    pub fn is_success(&self) -> bool {
        matches!(self, TxStatus::Success)
    }

    pub fn is_failed(&self) -> bool {
        !self.is_success()
    }

    pub fn error_message(&self) -> Option<&str> {
        match self {
            TxStatus::Success => None,
            TxStatus::Revert(reason) => Some(reason),
            TxStatus::InvalidNonce => Some("Invalid nonce"),
            TxStatus::InsufficientBalance => Some("Insufficient balance"),
            TxStatus::InvalidAmount => Some("Invalid amount"),
            TxStatus::InvalidOpcode => Some("Invalid opcode"),
            TxStatus::GasLimitExceeded => Some("Gas limit exceeded"),
            TxStatus::Other(reason) => Some(reason),
        }
    }
}

/// Transaction receipt containing execution results
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransactionReceipt {
    pub tx_hash: String,           // Hash of the transaction
    pub from: String,
    pub to: String,
    pub amount: u128,
    pub nonce: u64,
    pub status: TxStatus,
    pub gas_used: u64,
    pub gas_limit: u64,
    pub block_number: u64,
    pub transaction_index: usize,
    pub logs: Vec<String>,         // Event logs (simplified)
    pub return_data: Vec<u8>,      // Return data from execution
}

impl TransactionReceipt {
    pub fn new(
        tx_hash: String,
        from: String,
        to: String,
        amount: u128,
        nonce: u64,
        status: TxStatus,
        gas_used: u64,
        gas_limit: u64,
        block_number: u64,
        transaction_index: usize,
    ) -> Self {
        Self {
            tx_hash,
            from,
            to,
            amount,
            nonce,
            status,
            gas_used,
            gas_limit,
            block_number,
            transaction_index,
            logs: Vec::new(),
            return_data: Vec::new(),
        }
    }

    /// Calculate the hash of this receipt for Merkle tree inclusion
    pub fn hash(&self) -> String {
        let mut hasher = Sha256::new();
        hasher.update(self.tx_hash.as_bytes());
        hasher.update(self.from.as_bytes());
        hasher.update(self.to.as_bytes());
        hasher.update(self.amount.to_string().as_bytes());
        hasher.update(self.nonce.to_string().as_bytes());
        hasher.update(format!("{:?}", self.status).as_bytes());
        hasher.update(self.gas_used.to_string().as_bytes());
        hasher.update(self.gas_limit.to_string().as_bytes());
        hasher.update(self.block_number.to_string().as_bytes());
        hasher.update(self.transaction_index.to_string().as_bytes());
        
        // Include logs
        for log in &self.logs {
            hasher.update(log.as_bytes());
        }
        
        // Include return data
        hasher.update(&self.return_data);
        
        hex::encode(hasher.finalize())
    }

    /// Serialize receipt for inclusion in proof
    pub fn serialize(&self) -> Vec<u8> {
        serde_json::to_vec(self).unwrap_or_default()
    }
}

/// Block-level receipts management
#[derive(Debug, Clone)]
pub struct ReceiptsManager {
    receipts: HashMap<u64, Vec<TransactionReceipt>>, // block_number -> receipts
}

impl ReceiptsManager {
    pub fn new() -> Self {
        Self {
            receipts: HashMap::new(),
        }
    }

    /// Add a receipt for a specific block
    pub fn add_receipt(&mut self, block_number: u64, receipt: TransactionReceipt) {
        self.receipts.entry(block_number).or_insert_with(Vec::new).push(receipt);
    }

    /// Get all receipts for a block
    pub fn get_block_receipts(&self, block_number: u64) -> Option<&Vec<TransactionReceipt>> {
        self.receipts.get(&block_number)
    }

    /// Calculate the receipts root for a block (Merkle root of all receipts)
    pub fn calculate_receipts_root(&self, block_number: u64) -> String {
        if let Some(receipts) = self.get_block_receipts(block_number) {
            if receipts.is_empty() {
                return "0000000000000000000000000000000000000000000000000000000000000000".to_string();
            }
            
            // Simple Merkle tree implementation
            let mut hashes: Vec<String> = receipts.iter().map(|r| r.hash()).collect();
            
            while hashes.len() > 1 {
                let mut next_level = Vec::new();
                for i in (0..hashes.len()).step_by(2) {
                    let left = &hashes[i];
                    let right = if i + 1 < hashes.len() {
                        &hashes[i + 1]
                    } else {
                        left // Duplicate last element if odd number
                    };
                    
                    let mut hasher = Sha256::new();
                    hasher.update(left.as_bytes());
                    hasher.update(right.as_bytes());
                    next_level.push(hex::encode(hasher.finalize()));
                }
                hashes = next_level;
            }
            
            hashes[0].clone()
        } else {
            "0000000000000000000000000000000000000000000000000000000000000000".to_string()
        }
    }

    /// Get execution statistics for a block
    pub fn get_execution_stats(&self, block_number: u64) -> ExecutionStats {
        if let Some(receipts) = self.get_block_receipts(block_number) {
            let total_txs = receipts.len();
            let successful_txs = receipts.iter().filter(|r| r.status.is_success()).count();
            let failed_txs = total_txs - successful_txs;
            
            let mut failure_reasons = HashMap::new();
            for receipt in receipts {
                if receipt.status.is_failed() {
                    let reason = receipt.status.error_message().unwrap_or("Unknown");
                    *failure_reasons.entry(reason.to_string()).or_insert(0) += 1;
                }
            }
            
            ExecutionStats {
                total_transactions: total_txs,
                successful_transactions: successful_txs,
                failed_transactions: failed_txs,
                failure_reasons,
            }
        } else {
            ExecutionStats {
                total_transactions: 0,
                successful_transactions: 0,
                failed_transactions: 0,
                failure_reasons: HashMap::new(),
            }
        }
    }

    /// Clear receipts for a block
    pub fn clear_block_receipts(&mut self, block_number: u64) {
        self.receipts.remove(&block_number);
    }
}

/// Execution statistics for a block
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecutionStats {
    pub total_transactions: usize,
    pub successful_transactions: usize,
    pub failed_transactions: usize,
    pub failure_reasons: HashMap<String, usize>,
}

impl ExecutionStats {
    pub fn success_rate(&self) -> f64 {
        if self.total_transactions == 0 {
            0.0
        } else {
            self.successful_transactions as f64 / self.total_transactions as f64
        }
    }
}

/// Enhanced block commitment including receipts root
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlockCommitment {
    pub state_root: String,
    pub receipts_root: String,
    pub block_number: u64,
    pub prev_block_hash: String,
    pub timestamp: u64,
    pub proposer: String,
}

impl BlockCommitment {
    pub fn new(
        state_root: String,
        receipts_root: String,
        block_number: u64,
        prev_block_hash: String,
        timestamp: u64,
        proposer: String,
    ) -> Self {
        Self {
            state_root,
            receipts_root,
            block_number,
            prev_block_hash,
            timestamp,
            proposer,
        }
    }

    /// Calculate the block commitment hash
    pub fn hash(&self) -> String {
        let mut hasher = Sha256::new();
        hasher.update(self.state_root.as_bytes());
        hasher.update(self.receipts_root.as_bytes());
        hasher.update(self.block_number.to_string().as_bytes());
        hasher.update(self.prev_block_hash.as_bytes());
        hasher.update(self.timestamp.to_string().as_bytes());
        hasher.update(self.proposer.as_bytes());
        hex::encode(hasher.finalize())
    }
}
