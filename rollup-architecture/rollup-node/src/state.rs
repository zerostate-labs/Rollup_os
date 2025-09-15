use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::sync::Mutex;
use crate::receipt::{TransactionReceipt, TxStatus, ReceiptsManager, ExecutionStats};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Account {
    pub balance: u128,
    pub nonce: u64,
}

impl Account {
    pub fn new() -> Self {
        Self {
            balance: 0,
            nonce: 0,
        }
    }
}

#[derive(Debug)]
pub struct State {
    accounts: Mutex<HashMap<String, Account>>,
    last_block: Mutex<u64>,
    last_root: Mutex<String>,
    receipts_manager: Mutex<ReceiptsManager>,
}

impl State {
    pub fn new() -> Self {
        Self {
            accounts: Mutex::new(HashMap::new()),
            last_block: Mutex::new(0),
            last_root: Mutex::new("0000000000000000000000000000000000000000000000000000000000000000".to_string()),
            receipts_manager: Mutex::new(ReceiptsManager::new()),
        }
    }

    pub fn credit(&self, address: &str, amount: u128) {
        let mut accounts = self.accounts.lock().unwrap();
        let account = accounts.entry(address.to_string()).or_insert_with(Account::new);
        account.balance += amount;
    }

    pub fn get_acct(&self, address: &str) -> Account {
        let accounts = self.accounts.lock().unwrap();
        accounts.get(address).cloned().unwrap_or_else(Account::new)
    }

    pub fn apply_transfer(&self, from: &str, to: &str, amount: u128, nonce: u64) -> Result<(), String> {
        let mut accounts = self.accounts.lock().unwrap();
        
        // Validate nonce and balance first
        if let Some(acc) = accounts.get(from) {
            if acc.nonce != nonce {
                return Err(format!("Invalid nonce: expected {}, got {}", acc.nonce, nonce));
            }
            if acc.balance < amount {
                return Err(format!("Insufficient balance: {} < {}", acc.balance, amount));
            }
        } else {
            if nonce != 0 {
                return Err(format!("Invalid nonce: expected 0, got {}", nonce));
            }
        }
        
        {
            let from_account = accounts.entry(from.to_string()).or_insert_with(Account::new);
            from_account.balance -= amount;
            from_account.nonce += 1;
        }
        
        {
            let to_account = accounts.entry(to.to_string()).or_insert_with(Account::new);
            to_account.balance += amount;
        }
        
        Ok(())
    }

    /// Execute a transaction with detailed tracking and receipt generation
    pub fn execute_transaction(
        &self,
        from: &str,
        to: &str,
        amount: u128,
        nonce: u64,
        block_number: u64,
        transaction_index: usize,
        gas_limit: u64,
    ) -> TransactionReceipt {
        let tx_hash = self.calculate_tx_hash(from, to, amount, nonce);
        
        // Execute the transaction and capture the result
        let (status, gas_used) = match self.apply_transfer(from, to, amount, nonce) {
            Ok(_) => (TxStatus::Success, gas_limit / 2), // Mock gas usage
            Err(e) => {
                let status = if e.contains("Invalid nonce") {
                    TxStatus::InvalidNonce
                } else if e.contains("Insufficient balance") {
                    TxStatus::InsufficientBalance
                } else if e.contains("Invalid amount") {
                    TxStatus::InvalidAmount
                } else {
                    TxStatus::Other(e.clone())
                };
                (status, gas_limit) // Use all gas on failure
            }
        };

        // Create receipt
        let receipt = TransactionReceipt::new(
            tx_hash,
            from.to_string(),
            to.to_string(),
            amount,
            nonce,
            status,
            gas_used,
            gas_limit,
            block_number,
            transaction_index,
        );

        // Store receipt
        {
            let mut receipts_manager = self.receipts_manager.lock().unwrap();
            receipts_manager.add_receipt(block_number, receipt.clone());
        }

        receipt
    }

    /// Calculate transaction hash
    pub fn calculate_tx_hash(&self, from: &str, to: &str, amount: u128, nonce: u64) -> String {
        let mut hasher = Sha256::new();
        hasher.update(from.as_bytes());
        hasher.update(to.as_bytes());
        hasher.update(amount.to_string().as_bytes());
        hasher.update(nonce.to_string().as_bytes());
        hex::encode(hasher.finalize())
    }

    /// Get receipts root for a block
    pub fn get_receipts_root(&self, block_number: u64) -> String {
        let receipts_manager = self.receipts_manager.lock().unwrap();
        receipts_manager.calculate_receipts_root(block_number)
    }

    /// Get execution statistics for a block
    pub fn get_execution_stats(&self, block_number: u64) -> ExecutionStats {
        let receipts_manager = self.receipts_manager.lock().unwrap();
        receipts_manager.get_execution_stats(block_number)
    }

    /// Get all receipts for a block
    pub fn get_block_receipts(&self, block_number: u64) -> Option<Vec<TransactionReceipt>> {
        let receipts_manager = self.receipts_manager.lock().unwrap();
        receipts_manager.get_block_receipts(block_number).cloned()
    }

    pub fn get_last_block(&self) -> u64 {
        *self.last_block.lock().unwrap()
    }

    pub fn get_last_root(&self) -> String {
        self.last_root.lock().unwrap().clone()
    }

    pub fn commit_block(&self, block_number: u64) -> (u64, String) {
        let mut last_block = self.last_block.lock().unwrap();
        let mut last_root = self.last_root.lock().unwrap();
        
        *last_block = block_number;
        
        // Compute new state root (simplified - in real implementation this would be a proper Merkle tree)
        let accounts = self.accounts.lock().unwrap();
        let mut hasher = Sha256::new();
        hasher.update(block_number.to_string().as_bytes());
        
        for (addr, account) in accounts.iter() {
            hasher.update(addr.as_bytes());
            hasher.update(account.balance.to_string().as_bytes());
            hasher.update(account.nonce.to_string().as_bytes());
        }
        
        let result = hasher.finalize();
        *last_root = hex::encode(result);
        
        (block_number, last_root.clone())
    }
}
