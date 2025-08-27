#!/bin/bash

# Merged High-Performance Rollup Node Integration Test
# Combines working blob creation with enhanced error tracking and metrics

set -e

# Configuration
TRANSACTIONS_PER_BLOCK=100  # 100 transactions per block
BLOCKS_PER_BLOB=5          # 5 blocks per blob
TOTAL_TRANSACTIONS=2500    # Total transactions to submit (25 blocks × 100 transactions)
BATCH_SIZE=50              # Submit transactions in batches for better performance

# Metrics tracking
START_TIME=$(date +%s)
FAILED_TRANSACTIONS=0
SUCCESSFUL_TRANSACTIONS=0
NONCE_ERRORS=0
BALANCE_ERRORS=0
NETWORK_ERRORS=0

# Nonce tracking per account (local tracking only - like older script)
declare -A ACCOUNT_NONCES
ACCOUNT_NONCES["alice"]=0
ACCOUNT_NONCES["bob"]=0
ACCOUNT_NONCES["charlie"]=0
ACCOUNT_NONCES["diana"]=0

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
echo "  Expected blobs: $(( (25 + BLOCKS_PER_BLOB - 1) / BLOCKS_PER_BLOB ))"
echo "  Start time: $(date)"
echo ""

# Start the rollup node in background
echo "Starting rollup node..."
cargo run &
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
        
        # Select transaction pattern (optimized)
        local pattern_index=$((i % 8))
        case $pattern_index in
            0) from="alice"; to="bob" ;;
            1) from="bob"; to="charlie" ;;
            2) from="charlie"; to="diana" ;;
            3) from="diana"; to="alice" ;;
            4) from="alice"; to="charlie" ;;
            5) from="bob"; to="diana" ;;
            6) from="charlie"; to="alice" ;;
            7) from="diana"; to="bob" ;;
        esac
        
        local amount=$((100 + i * 5))
        local nonce=${ACCOUNT_NONCES[$from]}
        
        # Submit transaction with basic error tracking
        local response=$(curl -s -X POST http://localhost:8080/tx \
            -H "Content-Type: application/json" \
            -d "{\"from\": \"$from\", \"to\": \"$to\", \"amount\": \"$amount\", \"nonce\": $nonce}" \
            --max-time 2 2>/dev/null)
        
        # Check if response indicates success
        if echo "$response" | grep -q '"queued":true' 2>/dev/null; then
            successful=$((successful + 1))
            ACCOUNT_NONCES[$from]=$((nonce + 1))
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
    
    # Get final nonces
    alice_final=$(curl -s http://localhost:8080/state/alice --max-time 3 | jq -r '.nonce // 0')
    bob_final=$(curl -s http://localhost:8080/state/bob --max-time 3 | jq -r '.nonce // 0')
    charlie_final=$(curl -s http://localhost:8080/state/charlie --max-time 3 | jq -r '.nonce // 0')
    diana_final=$(curl -s http://localhost:8080/state/diana --max-time 3 | jq -r '.nonce // 0')
    
    # Count expected transactions per account based on our pattern
    local alice_expected=0
    local bob_expected=0
    local charlie_expected=0
    local diana_expected=0
    
    for i in $(seq 0 $((TOTAL_TRANSACTIONS - 1))); do
        local pattern_index=$((i % 8))
        case $pattern_index in
            0|4) alice_expected=$((alice_expected + 1)) ;;
            1|7) bob_expected=$((bob_expected + 1)) ;;
            2|6) charlie_expected=$((charlie_expected + 1)) ;;
            3|5) diana_expected=$((diana_expected + 1)) ;;
        esac
    done
    
    # Calculate actual failures
    local alice_failed=$((alice_expected - alice_final))
    local bob_failed=$((bob_expected - bob_final))
    local charlie_failed=$((charlie_expected - charlie_final))
    local diana_failed=$((diana_expected - diana_final))
    
    local total_execution_failures=$((alice_failed + bob_failed + charlie_failed + diana_failed))
    
    echo "Expected vs Actual Nonce Analysis:"
    echo "  Alice:   Expected $alice_expected, Actual $alice_final, Failed: $alice_failed"
    echo "  Bob:     Expected $bob_expected, Actual $bob_final, Failed: $bob_failed"
    echo "  Charlie: Expected $charlie_expected, Actual $charlie_final, Failed: $charlie_failed"
    echo "  Diana:   Expected $diana_expected, Actual $diana_final, Failed: $diana_failed"
    echo ""
    
    # Update counters with actual execution failures
    FAILED_TRANSACTIONS=$total_execution_failures
    SUCCESSFUL_TRANSACTIONS=$((TOTAL_TRANSACTIONS - total_execution_failures))
}

# Wait for node to start (from older script - simpler approach)
echo "Waiting for rollup node to start..."
for i in {1..15}; do
    if curl -s --max-time 2 http://localhost:8080/state/alice > /dev/null 2>&1; then
        echo "Rollup node is ready!"
        break
    fi
    if [ $i -eq 15 ]; then
        echo "Error: Rollup node failed to start after 15 attempts"
        exit 1
    fi
    echo -n "."
    sleep 1
done

NODE_START_TIME=$(date +%s)
echo "Rollup node started successfully (took $((NODE_START_TIME - START_TIME)) seconds)"

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
alice_state=$(curl -s http://localhost:8080/state/alice --max-time 3)
bob_state=$(curl -s http://localhost:8080/state/bob --max-time 3)
charlie_state=$(curl -s http://localhost:8080/state/charlie --max-time 3)
diana_state=$(curl -s http://localhost:8080/state/diana --max-time 3)

ACCOUNT_NONCES["alice"]=$(echo "$alice_state" | jq -r '.nonce // 0')
ACCOUNT_NONCES["bob"]=$(echo "$bob_state" | jq -r '.nonce // 0')
ACCOUNT_NONCES["charlie"]=$(echo "$charlie_state" | jq -r '.nonce // 0')
ACCOUNT_NONCES["diana"]=$(echo "$diana_state" | jq -r '.nonce // 0')

echo "Initial Account Balances:"
echo "-------------------------"
echo "$alice_state" | jq -r '"Alice:   " + .balance + " (nonce: " + (.nonce | tostring) + ")"'
echo "$bob_state" | jq -r '"Bob:     " + .balance + " (nonce: " + (.nonce | tostring) + ")"'
echo "$charlie_state" | jq -r '"Charlie: " + .balance + " (nonce: " + (.nonce | tostring) + ")"'
echo "$diana_state" | jq -r '"Diana:   " + .balance + " (nonce: " + (.nonce | tostring) + ")"'

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
        if block_response=$(curl -s -X POST http://localhost:8080/block/produce --max-time 10); then
            if echo "$block_response" | jq -e '.block_number' > /dev/null 2>&1; then
                echo "✓ Block $(echo "$block_response" | jq -r '.block_number') created"
                blocks_produced=$((blocks_produced + 1))
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
    remaining_response=$(curl -s -X POST http://localhost:8080/block/produce --max-time 10)
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
echo "Final Account Balances:"
echo "----------------------"
curl -s http://localhost:8080/state/alice --max-time 3 | jq -r '"Alice:   " + .balance + " (nonce: " + (.nonce | tostring) + ")"'
curl -s http://localhost:8080/state/bob --max-time 3 | jq -r '"Bob:     " + .balance + " (nonce: " + (.nonce | tostring) + ")"'
curl -s http://localhost:8080/state/charlie --max-time 3 | jq -r '"Charlie: " + .balance + " (nonce: " + (.nonce | tostring) + ")"'
curl -s http://localhost:8080/state/diana --max-time 3 | jq -r '"Diana:   " + .balance + " (nonce: " + (.nonce | tostring) + ")"'

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
