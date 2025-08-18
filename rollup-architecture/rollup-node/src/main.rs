use axum::{
    extract::{Path, State as AxState},
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};

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

use state::State as AppStateInner;

#[derive(Clone)]
struct AppState {
    inner: Arc<AppStateInner>,
    tx_queue: Arc<Mutex<Vec<Tx>>>,
    transactions_per_block: u64,
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
    blob_path: String,
    blob_hash: String,
    proof_len: usize,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Setup tracing
    tracing_subscriber::registry()
        .with(tracing_subscriber::fmt::layer())
        .init();

    // Instantiate global state
    let app_state = AppState {
        inner: Arc::new(AppStateInner::new()),
        tx_queue: Arc::new(Mutex::new(Vec::new())),
        transactions_per_block: 100, // Default: 10 transactions per block
    };

    // Seed demo accounts (Phase 0 convenience)
    app_state.inner.credit("alice", 1_000_000);
    app_state.inner.credit("bob", 1000);
    app_state.inner.credit("charlie", 500_000);
    app_state.inner.credit("diana", 750_000);

    // Build router
    let router = Router::new()
        .route("/tx", post(post_tx))
        .route("/block/produce", post(produce_block))
        .route("/state/:addr", get(get_state))
        .route("/config/tx-per-block", post(set_tx_per_block))
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

    // Apply transactions
    for t in &txs {
        if let Ok(amount) = t.amount.parse::<u128>() {
            if let Err(e) = app_state.inner.apply_transfer(&t.from, &t.to, amount, t.nonce) {
                tracing::warn!("tx failed: {:?} err={}", t, e);
            }
        } else {
            tracing::warn!("invalid amount in tx: {:?}", t);
        }
    }

    // Commit block and compute post root
    let (_bn, post_root) = app_state.inner.commit_block(next_block);

    // Oracle commit (mock)
    let oracle_commit = oracle_adapter::current_oracle_commit();

    // Build blob and write to local DA directory
    let blob = da_publisher::Blob {
        block_number: next_block,
        txs: txs.iter().map(|t| format!("{}=>{}:{}", &t.from, &t.to, &t.amount)).collect(),
        oracle_commit: oracle_commit.clone(),
        state_root: post_root.clone(),
    };

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

    // Generate mock proof for Phase 0
    let proof = proof_adapter::generate_mock_proof(&prev_root, &post_root, &blob_hash, &oracle_commit);

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
        blob_path,
        blob_hash,
        proof_len: proof.len(),
    };

    (StatusCode::OK, Json(serde_json::to_value(resp).unwrap()))
}
