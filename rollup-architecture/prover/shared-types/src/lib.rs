#![cfg_attr(not(feature = "std"), no_std)]

use serde::{Deserialize, Serialize};

#[cfg(not(feature = "std"))]
use alloc::{string::String, vec::Vec};

/// Witness data that the guest program reads and processes
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct Witness {
    pub program_version: u32,
    pub prior_state_root: [u8; 32],       // S
    pub block_number: u64,
    pub timestamp: u64,
    pub tx_root: [u8; 32],                // Merkle root of tx_list
    pub oracle_root: [u8; 32],            // Root over signed oracle entries
    pub blob_root: [u8; 32],              // Celestia blob root / CID hash (compressed)
    pub transactions: Vec<Transaction>,   // For now, include full transactions
    pub oracle_data: Vec<OracleEntry>,    // For now, include full oracle data
}

/// Public outputs that the guest program commits to the journal
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct PublicOutputs {
    pub program_version: u32,
    pub prior_state_root: [u8; 32],       // echo S for sanity
    pub post_state_root: [u8; 32],        // S'
    pub block_number: u64,
    pub tx_root: [u8; 32],
    pub oracle_root: [u8; 32],
    pub blob_root: [u8; 32],
}

/// Transaction structure matching the rollup node
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct Transaction {
    pub from: String,
    pub to: String,
    pub amount: String,
    pub nonce: u64,
}

/// Oracle data entry
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct OracleEntry {
    pub source: String,
    pub price: String,
    pub timestamp: u64,
    pub signature: String, // In production, this would be a proper signature
}

/// Account state structure
#[derive(Serialize, Deserialize, Debug, Clone)]
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
