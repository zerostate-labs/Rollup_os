#![cfg_attr(not(feature = "std"), no_std)]

use rollup_shared_types::{Account, Transaction, Witness, PublicOutputs};
use sha2::{Digest, Sha256};

#[cfg(feature = "std")]
use std::collections::HashMap as StdHashMap;

#[cfg(not(feature = "std"))]
use alloc::collections::HashMap as StdHashMap;

#[cfg(not(feature = "std"))]
use alloc::{string::String, vec::Vec};

/// Core state machine that can run deterministically
pub struct CoreState {
    accounts: StdHashMap<String, Account>,
    last_block: u64,
    last_root: [u8; 32],
}

impl CoreState {
    pub fn new() -> Self {
        Self {
            accounts: StdHashMap::new(),
            last_block: 0,
            last_root: [0u8; 32],
        }
    }

    pub fn credit(&mut self, address: &str, amount: u128) {
        let account = self.accounts.entry(address.to_string()).or_insert_with(Account::new);
        account.balance += amount;
    }

    pub fn get_account(&self, address: &str) -> Account {
        self.accounts.get(address).cloned().unwrap_or_else(Account::new)
    }

    pub fn apply_transfer(&mut self, from: &str, to: &str, amount: u128, nonce: u64) -> Result<(), String> {
        // Validate nonce and balance first
        if let Some(acc) = self.accounts.get(from) {
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
            let from_account = self.accounts.entry(from.to_string()).or_insert_with(Account::new);
            from_account.balance -= amount;
            from_account.nonce += 1;
        }
        
        {
            let to_account = self.accounts.entry(to.to_string()).or_insert_with(Account::new);
            to_account.balance += amount;
        }
        
        Ok(())
    }

    pub fn get_last_block(&self) -> u64 {
        self.last_block
    }

    pub fn get_last_root(&self) -> [u8; 32] {
        self.last_root
    }

    /// Initialize the internal last_root to a given prior state root.
    /// Intended for environments that reconstruct or verify the prior state
    /// externally and need to seed the core before executing a block.
    pub fn set_last_root(&mut self, prior_root: [u8; 32]) {
        self.last_root = prior_root;
    }

    pub fn compute_state_root(&self, block_number: u64) -> [u8; 32] {
        let mut hasher = Sha256::new();
        hasher.update(block_number.to_string().as_bytes());
        
        // Sort accounts for deterministic hashing
        let mut sorted_accounts: Vec<_> = self.accounts.iter().collect();
        sorted_accounts.sort_by_key(|(addr, _)| *addr);
        
        for (addr, account) in sorted_accounts {
            hasher.update(addr.as_bytes());
            hasher.update(account.balance.to_string().as_bytes());
            hasher.update(account.nonce.to_string().as_bytes());
        }
        
        let result = hasher.finalize();
        result.into()
    }

    pub fn commit_block(&mut self, block_number: u64) -> [u8; 32] {
        self.last_block = block_number;
        self.last_root = self.compute_state_root(block_number);
        self.last_root
    }

    /// Execute a block of transactions deterministically
    pub fn execute_block(&mut self, witness: &Witness) -> Result<PublicOutputs, String> {
        // Verify we're starting from the expected state
        if self.last_root != witness.prior_state_root {
            return Err("Prior state root mismatch".to_string());
        }

        // Apply all transactions
        for tx in &witness.transactions {
            let amount: u128 = tx.amount.parse().map_err(|_| "Invalid amount")?;
            self.apply_transfer(&tx.from, &tx.to, amount, tx.nonce)?;
        }

        // Compute new state root
        let post_state_root = self.compute_state_root(witness.block_number);
        
        // Update internal state
        self.last_block = witness.block_number;
        self.last_root = post_state_root;

        Ok(PublicOutputs {
            program_version: witness.program_version,
            prior_state_root: witness.prior_state_root,
            post_state_root,
            block_number: witness.block_number,
            tx_root: witness.tx_root,
            oracle_root: witness.oracle_root,
            blob_root: witness.blob_root,
        })
    }

    /// Compute transaction root from transaction list
    pub fn compute_tx_root(transactions: &[Transaction]) -> [u8; 32] {
        let mut hasher = Sha256::new();
        for tx in transactions {
            hasher.update(tx.from.as_bytes());
            hasher.update(tx.to.as_bytes());
            hasher.update(tx.amount.as_bytes());
            hasher.update(tx.nonce.to_string().as_bytes());
        }
        let result = hasher.finalize();
        result.into()
    }
}

#[cfg(feature = "std")]
impl Default for CoreState {
    fn default() -> Self {
        Self::new()
    }
}
