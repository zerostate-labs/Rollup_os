#!/bin/bash

# Merged High-Performance Rollup Node Integration Test
# Combines working blob creation with enhanced error tracking and metrics

set -e

# Configuration
TRANSACTIONS_PER_BLOCK=1000  # 1000 transactions per block
BLOCKS_PER_BLOB=5           # 5 blocks per blob
TOTAL_TRANSACTIONS=50000   # Total transactions to submit (50 blocks × 1000 transactions)
BATCH_SIZE=100             # Submit transactions in batches for better performance

# Account initialization will happen after node starts

# Metrics tracking
START_TIME=$(date +%s)
FAILED_TRANSACTIONS=0
SUCCESSFUL_TRANSACTIONS=0
NONCE_ERRORS=0
BALANCE_ERRORS=0
NETWORK_ERRORS=0

# Nonce tracking per account (local tracking only - like older script)
declare -A ACCOUNT_NONCES
# Stores on-chain starting nonces at the time we begin sending txs
declare -A STARTING_NONCES
# Local tracker for expected next nonce while submitting
declare -A LOCAL_TRACKED_NONCES
# Initialize 20 users with starting nonce of 0
for i in {1..20}; do
    ACCOUNT_NONCES["user$i"]=0
done

# Error tracking (from newer script)
declare -A ERROR_DETAILS
ERROR_DETAILS["nonce_errors"]=0
ERROR_DETAILS["balance_errors"]=0
ERROR_DETAILS["network_errors"]=0
ERROR_DETAILS["other_errors"]=0

echo "Starting Merged High-Performance Rollup Node Integration Test..."
echo "=============================================================="
echo "Configuration:"
echo "  Transactions per block: $TRANSACTIONS_PER_BLOCK"
echo "  Blocks per blob: $BLOCKS_PER_BLOB"
echo "  Total transactions: $TOTAL_TRANSACTIONS"
echo "  Batch size: $BATCH_SIZE"
echo "  Expected blocks: $(( (TOTAL_TRANSACTIONS + TRANSACTIONS_PER_BLOCK - 1) / TRANSACTIONS_PER_BLOCK ))"
echo "  Expected blobs: $(( (50 + BLOCKS_PER_BLOB - 1) / BLOCKS_PER_BLOB ))"
echo "  Start time: $(date)"
echo ""

# Start the rollup node in background
echo "Prebuilding rollup node (prover dev mode) to avoid startup timeout..."
RISC0_DEV_MODE=1 cargo build --release --features prover >/dev/null 2>&1 || true

echo "Starting rollup node (prover dev mode)..."
RISC0_DEV_MODE=1 RUST_LOG=info RISC0_INFO=1 cargo run --release --features prover > node.out 2>&1 &
NODE_PID=$!

# Function to cleanup on exit
cleanup() {
    echo ""
    echo "Cleaning up..."
    kill $NODE_PID 2>/dev/null || true
    wait $NODE_PID 2>/dev/null || true
}
trap cleanup EXIT

# Optimized batch transaction submission (from older script but with error tracking from newer)
submit_batch_transactions() {
    local start_index=$1
    local batch_size=$2
    local successful=0
    local failed=0
    
    for i in $(seq $start_index $((start_index + batch_size - 1))); do
        if [ $i -ge $TOTAL_TRANSACTIONS ]; then
            break
        fi
        
        # Randomly select sender and receiver (different users)
        local from_index=$((1 + RANDOM % 20))
        local to_index=$from_index
        while [ $to_index -eq $from_index ]; do
            to_index=$((1 + RANDOM % 20))
        done
        
        local from="user$from_index"
        local to="user$to_index"
        
        # Random amount between 1000 and 10000 to simulate real transactions
        local amount=$((1000 + RANDOM % 9001))
        local nonce=${LOCAL_TRACKED_NONCES[$from]}
        
        # Submit transaction with basic error tracking
        local response=$(curl -s -X POST http://localhost:8080/tx \
            -H "Content-Type: application/json" \
            -d "{\"from\": \"$from\", \"to\": \"$to\", \"amount\": \"$amount\", \"nonce\": $nonce}" \
            --max-time 2 2>/dev/null)
        
        # Check if response indicates success
        if echo "$response" | grep -q '"queued":true' 2>/dev/null; then
            successful=$((successful + 1))
            LOCAL_TRACKED_NONCES[$from]=$((nonce + 1))
        else
            failed=$((failed + 1))
            # Basic error classification
            if echo "$response" | grep -q "nonce" 2>/dev/null; then
                ERROR_DETAILS["nonce_errors"]=$((${ERROR_DETAILS["nonce_errors"]} + 1))
            elif echo "$response" | grep -q "balance" 2>/dev/null; then
                ERROR_DETAILS["balance_errors"]=$((${ERROR_DETAILS["balance_errors"]} + 1))
            elif [ -z "$response" ]; then
                ERROR_DETAILS["network_errors"]=$((${ERROR_DETAILS["network_errors"]} + 1))
            else
                ERROR_DETAILS["other_errors"]=$((${ERROR_DETAILS["other_errors"]} + 1))
            fi
        fi
        
        # Quick progress indicator
        if [ $((i % 100)) -eq 0 ]; then
            echo -n "."
        fi
    done
    
    SUCCESSFUL_TRANSACTIONS=$((SUCCESSFUL_TRANSACTIONS + successful))
    FAILED_TRANSACTIONS=$((FAILED_TRANSACTIONS + failed))
    
    echo " batch completed (✓$successful ✗$failed)"
}

# Function to analyze execution failures (simplified from newer script)
analyze_execution_failures() {
    echo ""
    echo "Analyzing Transaction Execution Results..."
    echo "========================================"
    
    # Get final nonces for all 20 users and compute actual successes from nonce deltas
    local total_success=0
    
    echo "User Nonce Analysis:"
    for i in {1..20}; do
        local user="user$i"
        local final_nonce=$(curl -s http://localhost:8080/state/$user --max-time 10 | jq -r '.nonce // 0')
        local starting_nonce=${STARTING_NONCES[$user]}
        # Guard empty values
        if [ -z "$starting_nonce" ]; then starting_nonce=0; fi
        if [ -z "$final_nonce" ]; then final_nonce=0; fi

        local actual_increment=$((final_nonce - starting_nonce))
        if [ $actual_increment -lt 0 ]; then
            actual_increment=0
        fi

        total_success=$((total_success + actual_increment))

        echo "  $user: Initial $starting_nonce, Final $final_nonce, Increment $actual_increment"
    done
    
    echo ""
    echo "Overall Analysis:"
    echo "  Total successful (by nonce deltas): $total_success"
    local total_failed=$((TOTAL_TRANSACTIONS - total_success))
    if [ $total_failed -lt 0 ]; then total_failed=0; fi
    if [ $total_failed -gt $TOTAL_TRANSACTIONS ]; then total_failed=$TOTAL_TRANSACTIONS; fi
    echo "  Estimated failures: $total_failed"
    echo ""
    
    # Update counters with actual execution failures
    FAILED_TRANSACTIONS=$total_failed
    SUCCESSFUL_TRANSACTIONS=$total_success
}

# Wait for node to start (from older script - simpler approach)
echo "Waiting for rollup node to start..."
for i in {1..120}; do
    if curl -s --max-time 2 http://localhost:8080/state/alice > /dev/null 2>&1; then
        echo "Rollup node is ready!"
        break
    fi
    if [ $i -eq 120 ]; then
        echo "Error: Rollup node failed to start after 120 attempts"
        echo "--- Last 100 lines of node.out ---"
        tail -n 100 node.out 2>/dev/null || true
        exit 1
    fi
    echo -n "."
    sleep 1
done

NODE_START_TIME=$(date +%s)
echo "Rollup node started successfully (took $((NODE_START_TIME - START_TIME)) seconds)"

# Initialize users with high balance to ensure sufficient funds for transactions
echo "Initializing 20 users with 1,000,000 units each..."
for i in {1..20}; do
    # Each user starts with 1,000,000 units to ensure they have enough for transactions
    curl -s -X POST http://localhost:8080/init_account \
        -H "Content-Type: application/json" \
        -d "{\"address\": \"user$i\", \"balance\": \"1000000\"}" \
        --max-time 10 >/dev/null 2>&1
done
echo "Initialized 20 users with 1,000,000 units each"

# Quick configuration (from older script)
echo ""
echo "Configuring node..."
curl -s -X POST http://localhost:8080/config/tx-per-block \
    -H "Content-Type: application/json" \
    -d "{\"transactions_per_block\": $TRANSACTIONS_PER_BLOCK}" --max-time 5 > /dev/null

curl -s -X POST http://localhost:8080/config/blocks-per-blob \
    -H "Content-Type: application/json" \
    -d "{\"blocks_per_blob\": $BLOCKS_PER_BLOB}" --max-time 5 > /dev/null

echo "Node configured successfully"

# Get initial state quickly (from older script approach)
echo ""
echo "Getting initial account states..."
for i in {1..20}; do
    user="user$i"
    user_state=$(curl -s http://localhost:8080/state/$user --max-time 10)
    nonce_val=$(echo "$user_state" | jq -r '.nonce // 0')
    ACCOUNT_NONCES[$user]=$nonce_val
    STARTING_NONCES[$user]=$nonce_val
    LOCAL_TRACKED_NONCES[$user]=$nonce_val
done

echo "Initial Account Balances (first 5 users):"
echo "----------------------------------------"
for i in {1..5}; do
    user="user$i"
    user_state=$(curl -s http://localhost:8080/state/$user --max-time 10)
    echo "$user_state" | jq -r '"'$user': " + .balance + " (nonce: " + (.nonce | tostring) + ")"'
done
echo "... (and 15 more users)"

# High-speed transaction processing (from older script)
echo ""
echo "Processing transactions at high speed..."
echo "========================================"

TRANSACTION_START_TIME=$(date +%s)
block_number=1
tx_count=0
blocks_produced=0

# Process transactions in batches (from older script)
for batch_start in $(seq 0 $BATCH_SIZE $((TOTAL_TRANSACTIONS - 1))); do
    echo -n "Processing batch starting at transaction $((batch_start + 1)): "
    submit_batch_transactions $batch_start $BATCH_SIZE
    
    tx_count=$((tx_count + BATCH_SIZE))
    
    # Check if we should produce blocks
    while [ $tx_count -ge $((block_number * TRANSACTIONS_PER_BLOCK)) ]; do
        echo ""
        echo "Producing Block $block_number (Progress: $tx_count/$TOTAL_TRANSACTIONS txs)..."
        
        # Fast block production (from older script approach)
        if block_response=$(curl -s -X POST http://localhost:8080/block/produce --max-time 30); then
            if echo "$block_response" | jq -e '.block_number' > /dev/null 2>&1; then
                echo "✓ Block $(echo "$block_response" | jq -r '.block_number') created | proof_len=$(echo "$block_response" | jq -r '.proof_len') verified=$(echo "$block_response" | jq -r '.proof_verified')"
                blocks_produced=$((blocks_produced + 1))
                # Save proof to file for demo
                proof_hex=$(echo "$block_response" | jq -r '.proof_hex')
                if [ "$proof_hex" != "null" ] && [ -n "$proof_hex" ]; then
                    echo "$proof_hex" | tr -d '\n' > "local-da/proof_block_$(echo "$block_response" | jq -r '.block_number').hex" 2>/dev/null || true
                fi
            else
                echo "⚠ Block production response: $block_response"
            fi
        else
            echo "✗ Block production failed"
        fi
        
        block_number=$((block_number + 1))
    done
    
    # Small pause to prevent overwhelming
    sleep 0.05
done

TRANSACTION_END_TIME=$(date +%s)

# Handle remaining transactions (from older script)
echo ""
echo "Producing final blocks..."
while true; do
    remaining_response=$(curl -s -X POST http://localhost:8080/block/produce --max-time 30)
    if echo "$remaining_response" | jq -e '.error' > /dev/null 2>&1; then
        echo "No more transactions to process"
        break
    else
        echo "✓ Final block $(echo "$remaining_response" | jq -r '.block_number') created"
        blocks_produced=$((blocks_produced + 1))
    fi
done

BLOCK_PRODUCTION_END_TIME=$(date +%s)

# Quick final state check
echo ""
echo "Final Account Balances (first 5 users):"
echo "--------------------------------------"
for i in {1..5}; do
    user="user$i"
    curl -s http://localhost:8080/state/$user --max-time 10 | jq -r '"'$user': " + .balance + " (nonce: " + (.nonce | tostring) + ")"'
done
echo "... (and 15 more users)"

# Analyze execution failures (from newer script)
analyze_execution_failures

# Quick DA verification
echo ""
echo "Verifying Data Availability..."
if [ -d "local-da" ]; then
    block_count=$(ls local-da/block_*.json 2>/dev/null | wc -l)
    echo "Blocks written to local-da: $block_count"
else
    echo "Warning: local-da directory not found"
    block_count=0
fi

# High-speed blob creation (from older script - this is the key part that works)
echo ""
echo "Creating Celestia Blobs (High Speed)..."
echo "======================================"

BLOB_START_TIME=$(date +%s)

# Generate block numbers for loading (from older script - simplified approach)
if [ $block_count -gt 0 ]; then
    echo "Loading blocks 1-$block_count for blob creation..."
    
    # Create JSON array efficiently (from older script)
    block_numbers_json="[$(seq -s, 1 $block_count)]"
    
    # Load blocks (from older script - simpler approach)
    if load_response=$(curl -s -X POST http://localhost:8080/blob/load-blocks \
        -H "Content-Type: application/json" \
        -d "{\"block_numbers\": $block_numbers_json}" --max-time 30); then
        
        loaded_blocks=$(echo "$load_response" | jq -r '.loaded_blocks // 0')
        echo "✓ Loaded $loaded_blocks blocks"
        
        # Create blobs (from older script - simpler approach)
        echo "Creating blobs from loaded blocks..."
        if create_response=$(curl -s -X POST http://localhost:8080/blob/create-from-blocks --max-time 30); then
            created_blobs=$(echo "$create_response" | jq -r '.created_blobs // 0')
            echo "✓ Created $created_blobs blobs"
        else
            echo "✗ Blob creation failed"
            created_blobs=0
        fi
    else
        echo "✗ Block loading failed"
        created_blobs=0
    fi
else
    created_blobs=0
fi

BLOB_END_TIME=$(date +%s)

# Final verification
echo ""
echo "Final Verification..."
total_blobs=$(curl -s -X GET http://localhost:8080/blob/list --max-time 5 | jq -r '.total // 0')
proof_files=$(ls -1 local-da/proof_block_*.hex 2>/dev/null | wc -l)

echo "Proof artifacts saved: $proof_files"
if [ "$proof_files" -gt 0 ]; then
    echo "Example proof (hex preview):"
    head -c 64 $(ls -1 local-da/proof_block_*.hex | head -n1) 2>/dev/null || true
    echo ""
fi

END_TIME=$(date +%s)

# Enhanced summary (combining metrics from both scripts)
echo ""
echo "MERGED HIGH-PERFORMANCE ROLLUP TEST COMPLETED!"
echo "=============================================="
echo ""
echo "🚀 EXECUTION SUMMARY:"
echo "===================="
echo "Timing Breakdown:"
echo "  - Node startup: $((NODE_START_TIME - START_TIME))s"
echo "  - Transaction processing: $((TRANSACTION_END_TIME - TRANSACTION_START_TIME))s"
echo "  - Block production: $((BLOCK_PRODUCTION_END_TIME - TRANSACTION_START_TIME))s"
echo "  - Blob creation: $((BLOB_END_TIME - BLOB_START_TIME))s"
echo "  - 🏁 TOTAL TIME: $((END_TIME - START_TIME))s"
echo ""
echo "📊 CORRECTED Transaction Statistics:"
echo "  - Total attempted: $TOTAL_TRANSACTIONS"
echo "  - ✅ Successful: $SUCCESSFUL_TRANSACTIONS"
echo "  - ❌ Failed: $FAILED_TRANSACTIONS"
echo "  - Success rate: $(( SUCCESSFUL_TRANSACTIONS * 100 / TOTAL_TRANSACTIONS ))%"
echo ""
echo "📋 Error Breakdown:"
echo "  - Nonce errors: ${ERROR_DETAILS["nonce_errors"]}"
echo "  - Balance errors: ${ERROR_DETAILS["balance_errors"]}"
echo "  - Network errors: ${ERROR_DETAILS["network_errors"]}"
echo "  - Other errors: ${ERROR_DETAILS["other_errors"]}"
echo ""
echo "🏗️ Block and Blob Statistics:"
echo "  - Blocks created: $block_count"
echo "  - Celestia blobs: $total_blobs"
echo "  - Expected blobs: $(( (block_count + BLOCKS_PER_BLOB - 1) / BLOCKS_PER_BLOB )) (${BLOCKS_PER_BLOB} blocks per blob)"
echo ""
echo "⚡ Performance Metrics:"
if [ $((TRANSACTION_END_TIME - TRANSACTION_START_TIME)) -gt 0 ]; then
    echo "  - TX throughput: $(( SUCCESSFUL_TRANSACTIONS / (TRANSACTION_END_TIME - TRANSACTION_START_TIME) )) tx/second"
fi
if [ $blocks_produced -gt 0 ] && [ $((BLOCK_PRODUCTION_END_TIME - TRANSACTION_START_TIME)) -gt 0 ]; then
    echo "  - Block production rate: $(( blocks_produced * 60 / (BLOCK_PRODUCTION_END_TIME - TRANSACTION_START_TIME) )) blocks/minute"
fi
echo "  - Batch processing: $BATCH_SIZE transactions per batch"
echo ""
echo "📁 Storage:"
if [ -d "local-da" ]; then
    total_files=$(find local-da -type f 2>/dev/null | wc -l)
    total_size=$(du -sh local-da 2>/dev/null | cut -f1 || echo "unknown")
    echo "  - Total files: $total_files"
    echo "  - Storage used: $total_size"
fi
echo ""
echo "✅ Test completed at: $(date)"
echo "🎯 Average processing speed: $(( TOTAL_TRANSACTIONS * 60 / (END_TIME - START_TIME) )) transactions/minute"

# Final performance assessment
if [ $FAILED_TRANSACTIONS -gt 0 ]; then
    echo ""
    echo "⚠️  FAILURE DETECTION: Found $FAILED_TRANSACTIONS failed transactions!"
    echo "   This version accurately detects execution failures by comparing expected vs actual nonce increments."
else
    echo ""
    echo "🎯 Perfect execution: All transactions successful!"
fi

# Performance grade calculation
TX_PER_SECOND=$(( TOTAL_TRANSACTIONS / (END_TIME - START_TIME) ))
if [ $TX_PER_SECOND -gt 100 ]; then
    PERFORMANCE_GRADE="🏆 EXCELLENT"
elif [ $TX_PER_SECOND -gt 50 ]; then
    PERFORMANCE_GRADE="🥇 VERY GOOD"
elif [ $TX_PER_SECOND -gt 25 ]; then
    PERFORMANCE_GRADE="🥈 GOOD"
else
    PERFORMANCE_GRADE="🥉 ACCEPTABLE"
fi

echo "🏅 Performance Grade: $PERFORMANCE_GRADE (${TX_PER_SECOND} tx/sec)"
echo ""
echo "🏁 MERGED TEST EXECUTION COMPLETE"
echo "================================"
