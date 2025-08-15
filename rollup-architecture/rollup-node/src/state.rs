use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::sync::Mutex;

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
}

impl State {
    pub fn new() -> Self {
        Self {
            accounts: Mutex::new(HashMap::new()),
            last_block: Mutex::new(0),
            last_root: Mutex::new("0000000000000000000000000000000000000000000000000000000000000000".to_string()),
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
