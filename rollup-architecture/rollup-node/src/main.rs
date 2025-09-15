use axum::{
    extract::{Path, State as AxState},
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};

use sha2::Digest;
use serde::{Deserialize, Serialize};
use std::{
    net::SocketAddr,
    sync::{Arc, Mutex},
};
use tokio::process::Command;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

mod da_publisher;
mod oracle_adapter;
mod proof_adapter;
mod state;
mod blob_builder;
mod receipt;

use state::State as AppStateInner;
use blob_builder::{BlobBuilder, BlobConfig};

#[derive(Clone)]
struct AppState {
    inner: Arc<AppStateInner>,
    tx_queue: Arc<Mutex<Vec<Tx>>>,
    transactions_per_block: u64,
    blob_builder: Arc<Mutex<BlobBuilder>>,
    // Optionally: settlement config (contract address, rpc URL) could be here
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct Tx {
    pub from: String,
    pub to: String,
    pub amount: String, // keep as string for simplicity in JSON
    pub nonce: u64,
}

#[derive(Serialize)]
struct TxAccepted {
    queued: bool,
}

#[derive(Serialize)]
struct ProduceResp {
    block_number: u64,
    pre_root: String,
    post_root: String,
    receipts_root: String,
    blob_path: String,
    blob_hash: String,
    proof_len: usize,
    proof_hex: String,
    proof_verified: bool,
    execution_stats: receipt::ExecutionStats,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Setup tracing
    tracing_subscriber::registry()
        .with(tracing_subscriber::fmt::layer())
        .init();

    // Instantiate global state
    let blob_config = BlobConfig {
        blocks_per_blob: 5,
        namespace_id: "0000000000000000".to_string(),
        share_version: 0,
    };
    
    let app_state = AppState {
        inner: Arc::new(AppStateInner::new()),
        tx_queue: Arc::new(Mutex::new(Vec::new())),
        transactions_per_block: 1000, // Default: 1000 transactions per block
        blob_builder: Arc::new(Mutex::new(BlobBuilder::new(blob_config))),
    };

    // Seed demo accounts (Phase 0 convenience)
    app_state.inner.credit("alice", 1_000_000);
    app_state.inner.credit("bob", 1000);
    app_state.inner.credit("charlie", 500_000);
    app_state.inner.credit("diana", 750_000);

    // Build router
    let router = Router::new()
        .route("/tx", post(post_tx))
        .route("/init_account", post(init_account))
        .route("/block/produce", post(produce_block))
        .route("/block/:block_number/receipts", get(get_block_receipts))
        .route("/block/:block_number/stats", get(get_block_stats))
        .route("/blob/create", post(create_blobs))
        .route("/blob/create-from-blocks", post(create_blobs_from_blocks))
        .route("/blob/load-blocks", post(load_blocks_from_storage))
        .route("/blob/list", get(list_blobs))
        .route("/state/:addr", get(get_state))
        .route("/config/tx-per-block", post(set_tx_per_block))
        .route("/config/blocks-per-blob", post(set_blocks_per_blob))
        .with_state(app_state.clone());

    let addr = SocketAddr::from(([127, 0, 0, 1], 8080));
    tracing::info!("Rollup node listening on http://{}", addr);
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, router).await?;

    Ok(())
}

/// POST /tx
async fn post_tx(
    AxState(app_state): AxState<AppState>,
    Json(tx): Json<Tx>,
) -> impl IntoResponse {
    // Basic validation could go here
    {
        let mut q = app_state.tx_queue.lock().unwrap();
        q.push(tx);
    }
    let resp = TxAccepted { queued: true };
    (StatusCode::OK, Json(resp))
}

/// GET /state/:addr
async fn get_state(
    AxState(app_state): AxState<AppState>,
    Path(addr): Path<String>,
) -> impl IntoResponse {
    let acct = app_state.inner.get_acct(&addr);
    let body = serde_json::json!({
        "address": addr,
        "nonce": acct.nonce,
        "balance": acct.balance.to_string(),
    });
    (StatusCode::OK, Json(body))
}

#[derive(Deserialize)]
struct InitAccountRequest {
    address: String,
    balance: String,
}

/// POST /init_account
async fn init_account(
    AxState(app_state): AxState<AppState>,
    Json(request): Json<InitAccountRequest>,
) -> impl IntoResponse {
    if let Ok(balance) = request.balance.parse::<u128>() {
        app_state.inner.credit(&request.address, balance);
        let response = serde_json::json!({
            "message": "Account initialized",
            "address": request.address,
            "balance": balance
        });
        (StatusCode::OK, Json(response))
    } else {
        let response = serde_json::json!({
            "error": "Invalid balance format"
        });
        (StatusCode::BAD_REQUEST, Json(response))
    }
}

#[derive(Deserialize)]
struct TxPerBlockConfig {
    transactions_per_block: u64,
}

/// POST /config/tx-per-block
async fn set_tx_per_block(
    AxState(mut app_state): AxState<AppState>,
    Json(config): Json<TxPerBlockConfig>,
) -> impl IntoResponse {
    if config.transactions_per_block == 0 {
        return (StatusCode::BAD_REQUEST, Json(serde_json::json!({
            "error": "transactions_per_block must be greater than 0"
        })));
    }
    
    app_state.transactions_per_block = config.transactions_per_block;
    
    let body = serde_json::json!({
        "message": "Configuration updated",
        "transactions_per_block": app_state.transactions_per_block
    });
    (StatusCode::OK, Json(body))
}

#[derive(Deserialize)]
struct BlocksPerBlobConfig {
    blocks_per_blob: usize,
}

/// POST /config/blocks-per-blob
async fn set_blocks_per_blob(
    AxState(app_state): AxState<AppState>,
    Json(config): Json<BlocksPerBlobConfig>,
) -> impl IntoResponse {
    if config.blocks_per_blob == 0 {
        return (StatusCode::BAD_REQUEST, Json(serde_json::json!({
            "error": "blocks_per_blob must be greater than 0"
        })));
    }
    
    let mut builder = app_state.blob_builder.lock().unwrap();
    builder.config.blocks_per_blob = config.blocks_per_blob;
    
    let body = serde_json::json!({
        "message": "Blob configuration updated",
        "blocks_per_blob": config.blocks_per_blob
    });
    (StatusCode::OK, Json(body))
}

async fn get_block_receipts(
    AxState(app_state): AxState<AppState>,
    Path(block_number): Path<u64>,
) -> impl IntoResponse {
    match app_state.inner.get_block_receipts(block_number) {
        Some(receipts) => {
            let response = serde_json::json!({
                "block_number": block_number,
                "receipts": receipts,
                "count": receipts.len()
            });
            (StatusCode::OK, Json(response))
        }
        None => {
            let response = serde_json::json!({
                "error": "Block not found",
                "block_number": block_number
            });
            (StatusCode::NOT_FOUND, Json(response))
        }
    }
}

async fn get_block_stats(
    AxState(app_state): AxState<AppState>,
    Path(block_number): Path<u64>,
) -> impl IntoResponse {
    let stats = app_state.inner.get_execution_stats(block_number);
    let receipts_root = app_state.inner.get_receipts_root(block_number);
    
    let response = serde_json::json!({
        "block_number": block_number,
        "receipts_root": receipts_root,
        "execution_stats": stats
    });
    
    (StatusCode::OK, Json(response))
}

/// POST /block/produce
/// Executes queued transactions, writes a DA blob (local file), generates a mock proof,
/// and optionally calls a settlement submit helper script (if present).
async fn produce_block(AxState(app_state): AxState<AppState>) -> impl IntoResponse {
    // Check if we have any transactions to produce a block
    let queue_size = {
        let q = app_state.tx_queue.lock().unwrap();
        q.len()
    };
    
    if queue_size == 0 {
        return (StatusCode::BAD_REQUEST, Json(serde_json::json!({
            "error": "No transactions in queue to produce block"
        })));
    }

    // Incremental block numbering using stored state.last_block
    let (prev_block, prev_root) = {
        // commit a "current" block number snapshot (we'll use state.commit_block to get prior root)
        // commit_block expects a block number; we'll compute next block, but we want prev root first
        let st = app_state.inner.clone();
        // prev block is current last_block
        let prev_block_num = {
            let inner = st.get_last_block();
            inner
        };
        let prev_root = st.get_last_root();
        (prev_block_num, prev_root)
    };

    let next_block = prev_block + 1;

    // Drain queue (take only first transactions_per_block transactions)
    let txs: Vec<Tx> = {
        let mut q = app_state.tx_queue.lock().unwrap();
        let mut drained = Vec::new();
        let tx_count = std::cmp::min(app_state.transactions_per_block as usize, q.len());
        for _ in 0..tx_count {
            drained.push(q.remove(0));
        }
        drained
    };

    // Execute transactions with detailed tracking
    let mut receipts = Vec::new();
    for (i, t) in txs.iter().enumerate() {
        if let Ok(amount) = t.amount.parse::<u128>() {
            let receipt = app_state.inner.execute_transaction(
                &t.from,
                &t.to,
                amount,
                t.nonce,
                next_block,
                i,
                21000, // Standard gas limit
            );
            receipts.push(receipt);
        } else {
            // Create a receipt for invalid amount
            let receipt = receipt::TransactionReceipt::new(
                app_state.inner.calculate_tx_hash(&t.from, &t.to, 0, t.nonce),
                t.from.clone(),
                t.to.clone(),
                0,
                t.nonce,
                receipt::TxStatus::InvalidAmount,
                21000,
                21000,
                next_block,
                i,
            );
            receipts.push(receipt);
        }
    }

    // Commit block and compute post root
    let (_bn, post_root) = app_state.inner.commit_block(next_block);

    // Get receipts root and execution stats
    let receipts_root = app_state.inner.get_receipts_root(next_block);
    let execution_stats = app_state.inner.get_execution_stats(next_block);

    // Oracle commit (mock)
    let oracle_commit = oracle_adapter::current_oracle_commit();

    // Build blob and write to local DA directory
    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    
    let txs_root = {
        let mut hasher = sha2::Sha256::new();
        for tx in &txs {
            hasher.update(format!("{}=>{}:{}", &tx.from, &tx.to, &tx.amount).as_bytes());
        }
        hex::encode(hasher.finalize())
    };

    let header = da_publisher::BlockHeader {
        parent_hash: prev_root.clone(),
        block_number: next_block,
        timestamp,
        proposer: "0x0000000000000000000000000000000000000000".to_string(),
        state_root: post_root.clone(),
        txs_root: txs_root.clone(),
        receipts_root: "0000000000000000000000000000000000000000000000000000000000000000".to_string(),
        da_pointer: "".to_string(),
        l1_finality_pointer: "".to_string(),
    };

    let execution_result = da_publisher::ExecutionResult {
        state_root: post_root.clone(),
        receipts_root: "0000000000000000000000000000000000000000000000000000000000000000".to_string(),
        gas_used: 0,
    };

    let blob = da_publisher::Blob {
        header,
        transactions: txs.iter().map(|t| format!("{}=>{}:{}", &t.from, &t.to, &t.amount)).collect(),
        execution_payload: execution_result,
        oracle_commit: oracle_commit.clone(),
        proofs: None,
    };

    // Add block to blob builder for later blob creation
    {
        let mut builder = app_state.blob_builder.lock().unwrap();
        builder.add_block(
            next_block,
            txs.iter().map(|t| format!("{}=>{}:{}", &t.from, &t.to, &t.amount)).collect(),
            timestamp,
        );
    }

    // Ensure local DA dir & write blob
    if let Err(e) = da_publisher::ensure_dir("local-da") {
        tracing::error!("failed to ensure local-da dir: {}", e);
        return (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({"error":"failed to prepare DA dir"})));
    }
    let (blob_path, blob_hash) = match da_publisher::write_blob("local-da", &blob) {
        Ok((p, h)) => (p, h),
        Err(e) => {
            tracing::error!("write_blob failed: {}", e);
            return (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({"error":"failed to write blob"})));
        }
    };

    let proof = proof_adapter::generate_proof(&prev_root, &post_root, &receipts_root, &blob_hash, &oracle_commit);
    let proof_verified = proof_adapter::verify_proof_unified(
        &proof,
        &prev_root,
        &post_root,
        &receipts_root,
        &blob_hash,
        &oracle_commit,
    );

    // Optionally submit to settlement via helper script (if exists)
    if std::path::Path::new("scripts/submit-settlement.js").exists() {
        // We will call Node script asynchronously and not block waiting too long
        let proof_hex = hex::encode(&proof);
        let block_str = next_block.to_string();
        let post_root_str = post_root.clone();
        let blob_hash_str = blob_hash.clone();
        tokio::spawn(async move {
            let status = Command::new("node")
                .arg("scripts/submit-settlement.js")
                .arg(block_str)
                .arg(post_root_str)
                .arg(blob_hash_str)
                .arg(proof_hex)
                .status()
                .await;
            match status {
                Ok(s) if s.success() => tracing::info!("submitted settlement ok"),
                Ok(s) => tracing::warn!("submit-settlement script returned {}", s),
                Err(e) => tracing::error!("failed to run submit-settlement.js: {}", e),
            }
        });
    }

    let resp = ProduceResp {
        block_number: next_block,
        pre_root: prev_root,
        post_root,
        receipts_root,
        blob_path,
        blob_hash,
        proof_len: proof.len(),
        proof_hex: hex::encode(&proof),
        proof_verified,
        execution_stats,
    };

    (StatusCode::OK, Json(serde_json::to_value(resp).unwrap()))
}

/// POST /blob/create - Create Celestia blobs from blocks in memory
async fn create_blobs(
    AxState(app_state): AxState<AppState>,
) -> impl IntoResponse {
    let mut builder = app_state.blob_builder.lock().unwrap();
    
    let blobs = match builder.create_blobs_from_blocks() {
        Ok(blobs) => blobs,
        Err(e) => {
            tracing::error!("failed to create blobs: {}", e);
            return (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({
                "error": "failed to create blobs"
            })));
        }
    };

    // Save blobs to local storage
    let mut saved_blobs = Vec::new();
    for (blob, metadata) in &blobs {
        match blob_builder::utils::save_blob("local-da", blob, metadata) {
            Ok(path) => {
                saved_blobs.push(serde_json::json!({
                    "blob_id": metadata.blob_id,
                    "path": path,
                    "commitment": metadata.commitment,
                    "transaction_count": metadata.transaction_count,
                    "block_numbers": metadata.block_numbers,
                }));
            }
            Err(e) => {
                tracing::error!("failed to save blob {}: {}", metadata.blob_id, e);
            }
        }
    }

    let response = serde_json::json!({
        "created_blobs": saved_blobs.len(),
        "blobs": saved_blobs,
        "blocks_processed": builder.block_count(),
        "total_transactions": builder.total_transaction_count(),
    });

    (StatusCode::OK, Json(response))
}

#[derive(Deserialize)]
struct LoadBlocksRequest {
    block_numbers: Vec<u64>,
}

/// POST /blob/load-blocks - Load blocks from storage into blob builder
async fn load_blocks_from_storage(
    AxState(app_state): AxState<AppState>,
    Json(request): Json<LoadBlocksRequest>,
) -> impl IntoResponse {
    let mut builder = app_state.blob_builder.lock().unwrap();
    let mut loaded_blocks = 0;
    let mut errors = Vec::new();

    for &block_number in &request.block_numbers {
        match blob_builder::utils::load_block("local-da", block_number) {
            Ok(block_data) => {
                builder.add_block(block_data.block_number, block_data.transactions, block_data.timestamp);
                loaded_blocks += 1;
            }
            Err(e) => {
                errors.push(format!("Block {}: {}", block_number, e));
            }
        }
    }

    let response = serde_json::json!({
        "loaded_blocks": loaded_blocks,
        "total_blocks_requested": request.block_numbers.len(),
        "errors": errors,
        "current_blocks_in_builder": builder.block_count(),
        "total_transactions": builder.total_transaction_count(),
    });

    (StatusCode::OK, Json(response))
}

/// POST /blob/create-from-blocks - Create blobs from blocks loaded in builder
async fn create_blobs_from_blocks(
    AxState(app_state): AxState<AppState>,
) -> impl IntoResponse {
    let mut builder = app_state.blob_builder.lock().unwrap();
    
    // Create blobs from loaded blocks
    let blobs = match builder.create_blobs_from_blocks() {
        Ok(blobs) => blobs,
        Err(e) => {
            tracing::error!("failed to create blobs from blocks: {}", e);
            return (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({
                "error": "failed to create blobs from blocks"
            })));
        }
    };

    // Save blobs to local storage
    let mut saved_blobs = Vec::new();
    for (blob, metadata) in &blobs {
        match blob_builder::utils::save_blob("local-da", blob, metadata) {
            Ok(path) => {
                saved_blobs.push(serde_json::json!({
                    "blob_id": metadata.blob_id,
                    "path": path,
                    "commitment": metadata.commitment,
                    "transaction_count": metadata.transaction_count,
                    "block_numbers": metadata.block_numbers,
                }));
            }
            Err(e) => {
                tracing::error!("failed to save blob {}: {}", metadata.blob_id, e);
            }
        }
    }

    let response = serde_json::json!({
        "created_blobs": saved_blobs.len(),
        "blobs": saved_blobs,
        "blocks_processed": builder.block_count(),
        "total_transactions": builder.total_transaction_count(),
    });

    (StatusCode::OK, Json(response))
}

/// GET /blob/list - List all created blobs
async fn list_blobs(
    AxState(_app_state): AxState<AppState>,
) -> impl IntoResponse {
    let blob_dir = std::path::Path::new("local-da").join("blobs");
    
    if !blob_dir.exists() {
        return (StatusCode::OK, Json(serde_json::json!({
            "blobs": [],
            "total": 0
        })));
    }

    let mut blobs = Vec::new();
    
    if let Ok(entries) = std::fs::read_dir(blob_dir) {
        for entry in entries {
            if let Ok(entry) = entry {
                if let Some(extension) = entry.path().extension() {
                    if extension == "json" {
                        if let Ok(metadata_json) = std::fs::read_to_string(entry.path()) {
                            if let Ok(metadata) = serde_json::from_str::<blob_builder::BlobMetadata>(&metadata_json) {
                                blobs.push(serde_json::json!({
                                    "blob_id": metadata.blob_id,
                                    "commitment": metadata.commitment,
                                    "transaction_count": metadata.transaction_count,
                                    "block_numbers": metadata.block_numbers,
                                    "created_at": metadata.created_at,
                                    "namespace_id": metadata.namespace_id,
                                }));
                            }
                        }
                    }
                }
            }
        }
    }

    // Sort by blob_id
    blobs.sort_by(|a, b| {
        let a_id = a["blob_id"].as_str().unwrap_or("");
        let b_id = b["blob_id"].as_str().unwrap_or("");
        a_id.cmp(b_id)
    });

    let response = serde_json::json!({
        "blobs": blobs,
        "total": blobs.len()
    });

    (StatusCode::OK, Json(response))
}
