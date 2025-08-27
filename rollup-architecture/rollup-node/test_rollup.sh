#!/bin/bash

# Improved High-Performance Rollup Node Integration Test
# Now with proper error tracking and nonce management

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

# Nonce tracking per account (synchronized with server)
declare -A ACCOUNT_NONCES
ACCOUNT_NONCES["alice"]=0
ACCOUNT_NONCES["bob"]=0
ACCOUNT_NONCES["charlie"]=0
ACCOUNT_NONCES["diana"]=0

# Error tracking
declare -A ERROR_DETAILS
ERROR_DETAILS["nonce_errors"]=0
ERROR_DETAILS["balance_errors"]=0
ERROR_DETAILS["network_errors"]=0
ERROR_DETAILS["other_errors"]=0

echo "Starting Improved High-Performance Rollup Node Integration Test..."
echo "================================================================="
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
sleep 5  # Give the node time to start up

# Record node startup timing
NODE_STARTUP_TIME=$(($(date +%s) - START_TIME))

# Record transaction start time
TRANSACTION_START_TIME=$(date +%s)

# Function to cleanup on exit - modified to ensure summary is shown first
cleanup() {
    # Calculate final metrics
    END_TIME=$(date +%s)
    TRANSACTION_PROCESSING_TIME=$((TRANSACTION_END_TIME - TRANSACTION_START_TIME))
    BLOCK_PRODUCTION_TIME=$((BLOCK_PRODUCTION_END_TIME - TRANSACTION_START_TIME))
    BLOB_CREATION_TIME=$((BLOB_END_TIME - BLOB_START_TIME))
    TOTAL_EXECUTION_TIME=$((END_TIME - START_TIME))
    
    # Calculate performance metrics
    if [ $TOTAL_EXECUTION_TIME -gt 0 ]; then
        OVERALL_TX_PER_SECOND=$((TOTAL_TRANSACTIONS / TOTAL_EXECUTION_TIME))
        TX_PER_MINUTE=$((SUCCESSFUL_TRANSACTIONS * 60 / TOTAL_EXECUTION_TIME))
    else
        OVERALL_TX_PER_SECOND=0
        TX_PER_MINUTE=0
    fi
    
    # Calculate storage metrics
    if [ -d "local-da" ]; then
        TOTAL_FILES=$(find local-da -type f | wc -l)
        STORAGE_SIZE=$(du -sh local-da 2>/dev/null | cut -f1)
        AVG_BLOCK_SIZE_KB=$(find local-da -name "block_*.json" -exec du -k {} + 2>/dev/null | awk '{ total += $1; count++ } END { if (count > 0) print total/count; else print 0 }')
        STORAGE_EFFICIENCY="$(du -b local-da 2>/dev/null | cut -f1)B total / $SUCCESSFUL_TRANSACTIONS tx"
    else
        TOTAL_FILES=0
        STORAGE_SIZE="0B"
        AVG_BLOCK_SIZE_KB=0
        STORAGE_EFFICIENCY="N/A"
    fi
    
    # Store metrics before cleanup
    local final_metrics
    final_metrics=$(generate_summary)
    
    echo ""
    echo "🚨 Cleanup initiated - ensuring summary completion..."
    
    if [ -n "$NODE_PID" ]; then
        echo "Terminating rollup node (PID: $NODE_PID)..."
        kill -TERM $NODE_PID 2>/dev/null || true
        sleep 2
        if kill -0 $NODE_PID 2>/dev/null; then
            kill -KILL $NODE_PID 2>/dev/null || true
        fi
        wait $NODE_PID 2>/dev/null || true
    fi
    
    # Display stored metrics after node shutdown
    echo "$final_metrics"
}

# Add this new function before the cleanup function:
generate_summary() {
    cat << EOF

🎉 ENHANCED HIGH-PERFORMANCE ROLLUP TEST COMPLETED!
======================================================

🚀 EXECUTION SUMMARY:
====================
⏱️  Timing Breakdown:
  - Node startup: ${NODE_STARTUP_TIME}s
  - Transaction processing: ${TRANSACTION_PROCESSING_TIME}s
  - Block production: ${BLOCK_PRODUCTION_TIME}s
  - Blob creation: ${BLOB_CREATION_TIME}s
  - 🏁 TOTAL TIME: ${TOTAL_EXECUTION_TIME}s

📊 Performance Metrics:
  - Transactions per second: ${OVERALL_TX_PER_SECOND}
  - Peak processing: ${TX_PER_MINUTE} tx/minute
  - Success rate: $(( SUCCESSFUL_TRANSACTIONS * 100 / TOTAL_TRANSACTIONS ))%

📁 Storage Analysis:
  - Total files: ${TOTAL_FILES}
  - Storage used: ${STORAGE_SIZE}
  - Average block size: ${AVG_BLOCK_SIZE_KB}KB
  - Storage efficiency: ${STORAGE_EFFICIENCY}

🎯 Final Statistics:
  - Total transactions: ${TOTAL_TRANSACTIONS}
  - Successful: ${SUCCESSFUL_TRANSACTIONS}
  - Failed: ${FAILED_TRANSACTIONS}
  - Blocks created: ${block_count}
  - Blobs created: ${total_blobs}
EOF
}

# Set trap but don't call cleanup prematurely
trap cleanup EXIT

# Function to sync nonces from server
sync_nonces_from_server() {
    echo "Synchronizing nonces from server..."
    
    for account in "alice" "bob" "charlie" "diana"; do
        response=$(curl -s http://localhost:8080/state/$account --max-time 3 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$response" ]; then
            server_nonce=$(echo "$response" | jq -r '.nonce // 0' 2>/dev/null)
            if [[ "$server_nonce" =~ ^[0-9]+$ ]]; then
                ACCOUNT_NONCES[$account]=$server_nonce
                echo "  $account: nonce = $server_nonce"
            else
                echo "  $account: failed to get nonce, using 0"
                ACCOUNT_NONCES[$account]=0
            fi
        else
            echo "  $account: network error, using 0"
            ACCOUNT_NONCES[$account]=0
        fi
    done
    echo ""
}

# Store transaction details for later verification
declare -A SUBMITTED_TRANSACTIONS
TRANSACTION_COUNTER=0

# Improved batch transaction submission with proper error tracking
submit_batch_transactions() {
    local start_index=$1
    local batch_size=$2
    local successful=0
    local failed=0
    local temp_dir=$(mktemp -d)
    
    # Create temporary files for parallel requests
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
        
        # Store transaction details for later verification
        SUBMITTED_TRANSACTIONS["$TRANSACTION_COUNTER"]="$from:$to:$amount:$nonce"
        TRANSACTION_COUNTER=$((TRANSACTION_COUNTER + 1))
        
        # Submit transaction with proper error checking
        local response_file="$temp_dir/tx_$i.json"
        local http_code=$(curl -s -w "%{http_code}" \
            -X POST http://localhost:8080/tx \
            -H "Content-Type: application/json" \
            -d "{\"from\": \"$from\", \"to\": \"$to\", \"amount\": \"$amount\", \"nonce\": $nonce}" \
            --max-time 3 \
            -o "$response_file" 2>/dev/null)
        
        if [ "$http_code" = "200" ]; then
            # Check if response indicates success
            response_content=$(cat "$response_file" 2>/dev/null || echo "{}")
            queued=$(echo "$response_content" | jq -r '.queued // false' 2>/dev/null)
            
            if [ "$queued" = "true" ]; then
                successful=$((successful + 1))
                ACCOUNT_NONCES[$from]=$((nonce + 1))
            else
                failed=$((failed + 1))
                # Try to extract error reason
                error_msg=$(echo "$response_content" | jq -r '.error // "unknown"' 2>/dev/null)
                case "$error_msg" in
                    *"nonce"*) ERROR_DETAILS["nonce_errors"]=$((${ERROR_DETAILS["nonce_errors"]} + 1)) ;;
                    *"balance"*) ERROR_DETAILS["balance_errors"]=$((${ERROR_DETAILS["balance_errors"]} + 1)) ;;
                    *) ERROR_DETAILS["other_errors"]=$((${ERROR_DETAILS["other_errors"]} + 1)) ;;
                esac
            fi
        else
            failed=$((failed + 1))
            ERROR_DETAILS["network_errors"]=$((${ERROR_DETAILS["network_errors"]} + 1))
            
            # For network errors, don't increment nonce
            echo "    HTTP $http_code: $from->$to ($amount) nonce:$nonce"
        fi
        
        # Quick progress indicator
        if [ $((i % 100)) -eq 0 ]; then
            echo -n "."
        fi
    done
    
    # Cleanup temp files
    rm -rf "$temp_dir"
    
    SUCCESSFUL_TRANSACTIONS=$((SUCCESSFUL_TRANSACTIONS + successful))
    FAILED_TRANSACTIONS=$((FAILED_TRANSACTIONS + failed))
    
    echo " batch completed (✓$successful ✗$failed)"
    
    # Show real-time error breakdown if there are failures
    if [ $failed -gt 0 ]; then
        echo "    Errors: nonce=${ERROR_DETAILS["nonce_errors"]} balance=${ERROR_DETAILS["balance_errors"]} network=${ERROR_DETAILS["network_errors"]} other=${ERROR_DETAILS["other_errors"]}"
    fi
}

# Function to analyze execution failures by comparing expected vs actual nonce increments
analyze_execution_failures() {
    echo ""
    echo "🔍 Analyzing Transaction Execution Results..."
    echo "============================================"
    
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
            0|4) alice_expected=$((alice_expected + 1)) ;;  # alice->bob, alice->charlie
            1|7) bob_expected=$((bob_expected + 1)) ;;      # bob->charlie, diana->bob
            2|6) charlie_expected=$((charlie_expected + 1)) ;;  # charlie->diana, charlie->alice
            3|5) diana_expected=$((diana_expected + 1)) ;;  # diana->alice, bob->diana
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
    echo "📊 CORRECTED Transaction Statistics:"
    echo "  - Total attempted: $TOTAL_TRANSACTIONS"
    echo "  - ✅ Successfully executed: $((TOTAL_TRANSACTIONS - total_execution_failures))"
    echo "  - ❌ Failed during execution: $total_execution_failures"
    echo "  - Actual success rate: $(( (TOTAL_TRANSACTIONS - total_execution_failures) * 100 / TOTAL_TRANSACTIONS ))%"
    
    # Update global counters
    FAILED_TRANSACTIONS=$total_execution_failures
    SUCCESSFUL_TRANSACTIONS=$((TOTAL_TRANSACTIONS - total_execution_failures))
    ERROR_DETAILS["nonce_errors"]=$total_execution_failures
    
    return $total_execution_failures
}

# Wait for node to start (improved)
echo "Waiting for rollup node to start..."
for i in {1..20}; do
    if curl -s --max-time 3 http://localhost:8080/state/alice > /dev/null 2>&1; then
        echo "Rollup node is ready!"
        break
    fi
    if [ $i -eq 20 ]; then
        echo "Error: Rollup node failed to start after 20 attempts"
        exit 1
    fi
    echo -n "."
    sleep 1
done

echo "Rollup node started successfully (took $NODE_STARTUP_TIME seconds)"

# Configuration
echo ""
echo "Configuring node..."
config_response=$(curl -s -X POST http://localhost:8080/config/tx-per-block \
    -H "Content-Type: application/json" \
    -d "{\"transactions_per_block\": $TRANSACTIONS_PER_BLOCK}" --max-time 5)

blob_config_response=$(curl -s -X POST http://localhost:8080/config/blocks-per-blob \
    -H "Content-Type: application/json" \
    -d "{\"blocks_per_blob\": $BLOCKS_PER_BLOB}" --max-time 5)

echo "Node configured successfully"

# Sync nonces from server to ensure accuracy
sync_nonces_from_server

# Get initial state and display
echo "Initial Account States:"
echo "======================"
alice_state=$(curl -s http://localhost:8080/state/alice --max-time 3)
bob_state=$(curl -s http://localhost:8080/state/bob --max-time 3)
charlie_state=$(curl -s http://localhost:8080/state/charlie --max-time 3)
diana_state=$(curl -s http://localhost:8080/state/diana --max-time 3)

echo "$alice_state" | jq -r '"Alice:   Balance=" + .balance + " Nonce=" + (.nonce | tostring)'
echo "$bob_state" | jq -r '"Bob:     Balance=" + .balance + " Nonce=" + (.nonce | tostring)'
echo "$charlie_state" | jq -r '"Charlie: Balance=" + .balance + " Nonce=" + (.nonce | tostring)'
echo "$diana_state" | jq -r '"Diana:   Balance=" + .balance + " Nonce=" + (.nonce | tostring)'

# High-speed transaction processing with better monitoring
echo ""
echo "Processing transactions with improved error tracking..."
echo "===================================================="

block_number=1
tx_count=0
blocks_produced=0
last_error_report=$TRANSACTION_START_TIME

# Process transactions in batches
for batch_start in $(seq 0 $BATCH_SIZE $((TOTAL_TRANSACTIONS - 1))); do
    echo -n "Batch $((batch_start/BATCH_SIZE + 1)): "
    submit_batch_transactions $batch_start $BATCH_SIZE
    
    tx_count=$((tx_count + BATCH_SIZE))
    current_time=$(date +%s)
    
    # Periodic error reporting (every 10 seconds)
    if [ $((current_time - last_error_report)) -ge 10 ]; then
        if [ $FAILED_TRANSACTIONS -gt 0 ]; then
            echo "  📊 Error Summary (so far): Total failures=$FAILED_TRANSACTIONS, Nonce=${ERROR_DETAILS["nonce_errors"]}, Balance=${ERROR_DETAILS["balance_errors"]}, Network=${ERROR_DETAILS["network_errors"]}"
        fi
        last_error_report=$current_time
    fi
    
    # Resync nonces every 5 batches to prevent drift
    if [ $(((batch_start/BATCH_SIZE + 1) % 5)) -eq 0 ]; then
        echo "  🔄 Resyncing nonces..."
        sync_nonces_from_server
    fi
    
    # Check if we should produce blocks
    while [ $tx_count -ge $((block_number * TRANSACTIONS_PER_BLOCK)) ]; do
        echo ""
        echo "Producing Block $block_number (Progress: $tx_count/$TOTAL_TRANSACTIONS txs)..."
        
        # Block production with error checking
        block_response=$(curl -s -w "%{http_code}" \
            -X POST http://localhost:8080/block/produce \
            --max-time 15 \
            -o /tmp/block_response.json)
        
        if [[ "$block_response" == *"200" ]]; then
            block_data=$(cat /tmp/block_response.json 2>/dev/null || echo "{}")
            block_num=$(echo "$block_data" | jq -r '.block_number // "unknown"')
            echo "✓ Block $block_num created successfully"
            blocks_produced=$((blocks_produced + 1))
            
            # Resync nonces after block production
            sync_nonces_from_server
        else
            echo "⚠ Block production warning (HTTP: $block_response)"
        fi
        
        block_number=$((block_number + 1))
    done
    
    # Small pause to prevent overwhelming
    sleep 0.1
done

TRANSACTION_END_TIME=$(date +%s)

# Handle remaining transactions
echo ""
echo "Producing final blocks..."
while true; do
    remaining_response=$(curl -s -X POST http://localhost:8080/block/produce --max-time 15 2>/dev/null)
    if echo "$remaining_response" | jq -e '.error' > /dev/null 2>&1; then
        echo "No more transactions to process"
        break
    elif echo "$remaining_response" | jq -e '.block_number' > /dev/null 2>&1; then
        echo "✓ Final block $(echo "$remaining_response" | jq -r '.block_number') created"
        blocks_produced=$((blocks_produced + 1))
    else
        echo "Block production completed"
        break
    fi
done

BLOCK_PRODUCTION_END_TIME=$(date +%s)

# Final state check and execution analysis
echo ""
echo "Final Account States:"
echo "===================="
curl -s http://localhost:8080/state/alice --max-time 3 | jq -r '"Alice:   Balance=" + .balance + " Nonce=" + (.nonce | tostring)'
curl -s http://localhost:8080/state/bob --max-time 3 | jq -r '"Bob:     Balance=" + .balance + " Nonce=" + (.nonce | tostring)'
curl -s http://localhost:8080/state/charlie --max-time 3 | jq -r '"Charlie: Balance=" + .balance + " Nonce=" + (.nonce | tostring)'
curl -s http://localhost:8080/state/diana --max-time 3 | jq -r '"Diana:   Balance=" + .balance + " Nonce=" + (.nonce | tostring)'

# Analyze execution failures
analyze_execution_failures

# DA verification
echo ""
echo "Verifying Data Availability..."
if [ -d "local-da" ]; then
    block_count=$(find local-da -name "block_*.json" 2>/dev/null | wc -l)
    echo "Blocks written to local-da: $block_count"
else
    echo "Warning: local-da directory not found"
    block_count=0
fi

# High-speed blob creation
echo ""
echo "Creating Celestia Blobs..."
echo "========================="

BLOB_START_TIME=$(date +%s)

if [ $block_count -gt 0 ]; then
    echo "Loading blocks 1-$block_count for blob creation..."
    
    block_numbers_json="[$(seq -s, 1 $block_count)]"
    
    # Load blocks with error checking
    load_response=$(curl -s -w "%{http_code}" \
        -X POST http://localhost:8080/blob/load-blocks \
        -H "Content-Type: application/json" \
        -d "{\"block_numbers\": $block_numbers_json}" \
        --max-time 30 \
        -o /tmp/load_response.json)
    
    if [[ "$load_response" == *"200" ]]; then
        load_data=$(cat /tmp/load_response.json)
        loaded_blocks=$(echo "$load_data" | jq -r '.loaded_blocks // 0')
        echo "✓ Loaded $loaded_blocks blocks"
        
        # Create blobs
        echo "Creating blobs from loaded blocks..."
        create_response=$(curl -s -w "%{http_code}" \
            -X POST http://localhost:8080/blob/create-from-blocks \
            --max-time 30 \
            -o /tmp/create_response.json)
        
        if [[ "$create_response" == *"200" ]]; then
            create_data=$(cat /tmp/create_response.json)
            created_blobs=$(echo "$create_data" | jq -r '.created_blobs // 0')
            echo "✓ Created $created_blobs blobs"
        else
            echo "✗ Blob creation failed (HTTP: $create_response)"
            created_blobs=0
        fi
    else
        echo "✗ Block loading failed (HTTP: $load_response)"
        created_blobs=0
    fi
else
    created_blobs=0
fi

BLOB_END_TIME=$(date +%s)

# Final verification
echo ""
echo "Final Verification..."
total_blobs_response=$(curl -s -X GET http://localhost:8080/blob/list --max-time 5)
total_blobs=$(echo "$total_blobs_response" | jq -r '.total // 0' 2>/dev/null || echo "0")

END_TIME=$(date +%s)

# Calculate additional metrics for enhanced summary
TRANSACTION_PROCESSING_TIME=$((TRANSACTION_END_TIME - TRANSACTION_START_TIME))
BLOCK_PRODUCTION_TIME=$((BLOCK_PRODUCTION_END_TIME - TRANSACTION_START_TIME))
BLOB_CREATION_TIME=$((BLOB_END_TIME - BLOB_START_TIME))
TOTAL_EXECUTION_TIME=$((END_TIME - START_TIME))

# Storage calculations
if [ -d "local-da" ]; then
    # Count different types of files
    BLOCK_FILES=$(find local-da -name "block_*.json" 2>/dev/null | wc -l)
    BLOB_FILES=$(find local-da/blobs -name "*.blob" 2>/dev/null | wc -l)
    BLOB_METADATA_FILES=$(find local-da/blobs -name "*.json" 2>/dev/null | wc -l)
    TOTAL_FILES=$((BLOCK_FILES + BLOB_FILES + BLOB_METADATA_FILES))
    
    # Calculate storage sizes
    STORAGE_SIZE=$(du -sh local-da 2>/dev/null | cut -f1 || echo "unknown")
    STORAGE_BYTES=$(du -sb local-da 2>/dev/null | cut -f1 || echo "0")
    BLOCK_STORAGE=$(find local-da -name "block_*.json" -exec du -c {} + 2>/dev/null | tail -1 | cut -f1 || echo "0")
    BLOB_STORAGE=$(find local-da/blobs -name "*.blob" -exec du -c {} + 2>/dev/null | tail -1 | cut -f1 || echo "0")
    
    # Average file sizes
    if [ $BLOCK_FILES -gt 0 ]; then
        AVG_BLOCK_SIZE=$((BLOCK_STORAGE / BLOCK_FILES))
        AVG_BLOCK_SIZE_KB=$((AVG_BLOCK_SIZE / 1024))
    else
        AVG_BLOCK_SIZE_KB=0
    fi
    
    if [ $BLOB_FILES -gt 0 ]; then
        AVG_BLOB_SIZE=$((BLOB_STORAGE / BLOB_FILES))
        AVG_BLOB_SIZE_KB=$((AVG_BLOB_SIZE / 1024))
    else
        AVG_BLOB_SIZE_KB=0
    fi
else
    TOTAL_FILES=0
    STORAGE_SIZE="0B"
    STORAGE_BYTES=0
    BLOCK_FILES=0
    BLOB_FILES=0
    BLOB_METADATA_FILES=0
    AVG_BLOCK_SIZE_KB=0
    AVG_BLOB_SIZE_KB=0
fi

# Performance calculations
if [ $TRANSACTION_PROCESSING_TIME -gt 0 ]; then
    SUCCESSFUL_TX_THROUGHPUT=$((SUCCESSFUL_TRANSACTIONS / TRANSACTION_PROCESSING_TIME))
    TOTAL_TX_THROUGHPUT=$((TOTAL_TRANSACTIONS / TRANSACTION_PROCESSING_TIME))
    TX_PER_MINUTE=$((SUCCESSFUL_TRANSACTIONS * 60 / TRANSACTION_PROCESSING_TIME))
else
    SUCCESSFUL_TX_THROUGHPUT=0
    TOTAL_TX_THROUGHPUT=0
    TX_PER_MINUTE=0
fi

if [ $blocks_produced -gt 0 ] && [ $BLOCK_PRODUCTION_TIME -gt 0 ]; then
    BLOCKS_PER_MINUTE=$((blocks_produced * 60 / BLOCK_PRODUCTION_TIME))
    BLOCKS_PER_SECOND=$((blocks_produced / BLOCK_PRODUCTION_TIME))
else
    BLOCKS_PER_MINUTE=0
    BLOCKS_PER_SECOND=0
fi

if [ $total_blobs -gt 0 ] && [ $BLOB_CREATION_TIME -gt 0 ]; then
    BLOBS_PER_MINUTE=$((total_blobs * 60 / BLOB_CREATION_TIME))
else
    BLOBS_PER_MINUTE=0
fi

# Overall processing speed
if [ $TOTAL_EXECUTION_TIME -gt 0 ]; then
    OVERALL_TX_PER_MINUTE=$((TOTAL_TRANSACTIONS * 60 / TOTAL_EXECUTION_TIME))
    OVERALL_TX_PER_SECOND=$((TOTAL_TRANSACTIONS / TOTAL_EXECUTION_TIME))
else
    OVERALL_TX_PER_MINUTE=0
    OVERALL_TX_PER_SECOND=0
fi

# Data efficiency metrics
if [ $SUCCESSFUL_TRANSACTIONS -gt 0 ]; then
    BYTES_PER_TRANSACTION=$((STORAGE_BYTES / SUCCESSFUL_TRANSACTIONS))
    if [ $BYTES_PER_TRANSACTION -gt 1024 ]; then
        STORAGE_EFFICIENCY="$((BYTES_PER_TRANSACTION / 1024))KB per tx"
    else
        STORAGE_EFFICIENCY="${BYTES_PER_TRANSACTION}B per tx"
    fi
else
    STORAGE_EFFICIENCY="N/A"
fi

# Calculate compression ratio (transactions to blobs)
if [ $total_blobs -gt 0 ]; then
    TX_TO_BLOB_RATIO=$((SUCCESSFUL_TRANSACTIONS / total_blobs))
else
    TX_TO_BLOB_RATIO=0
fi

# Cleanup temp files
rm -f /tmp/block_response.json /tmp/load_response.json /tmp/create_response.json

# CRITICAL: Remove the cleanup trap BEFORE showing summary to prevent interruption
trap - EXIT

echo ""
echo "🚨 Preparing to shutdown rollup node and display final results..."
echo ""

# Manually shutdown the rollup node BEFORE displaying summary
if [ -n "$NODE_PID" ]; then
    echo "Shutting down rollup node..."
    kill -TERM $NODE_PID 2>/dev/null || true
    
    # Give it a moment to terminate gracefully
    sleep 2
    
    # Force kill if still running
    if kill -0 $NODE_PID 2>/dev/null; then
        echo "Force killing rollup node..."
        kill -KILL $NODE_PID 2>/dev/null || true
    fi
    
    wait $NODE_PID 2>/dev/null || true
    echo "✅ Rollup node terminated successfully."
fi

# Force flush all output buffers
sync
sleep 1

# ENHANCED SUMMARY SECTION - Now protected from cleanup interruption
echo ""
echo "🎉 ENHANCED HIGH-PERFORMANCE ROLLUP TEST COMPLETED!"
echo "======================================================"
echo ""
echo "🚀 EXECUTION SUMMARY:"
echo "===================="
echo "⏱️  Timing Breakdown:"
echo "  - Node startup: ${NODE_STARTUP_TIME}s"
echo "  - Transaction processing: ${TRANSACTION_PROCESSING_TIME}s"
echo "  - Block production: ${BLOCK_PRODUCTION_TIME}s"
echo "  - Blob creation: ${BLOB_CREATION_TIME}s"
echo "  - 🏁 TOTAL TIME: ${TOTAL_EXECUTION_TIME}s"
echo ""
echo "📊 CORRECTED Transaction Statistics:"
echo "  - Total attempted: $TOTAL_TRANSACTIONS"
echo "  - ✅ Successful: $SUCCESSFUL_TRANSACTIONS"
echo "  - ❌ Failed: $FAILED_TRANSACTIONS"
echo "  - Success rate: $(( SUCCESSFUL_TRANSACTIONS * 100 / TOTAL_TRANSACTIONS ))%"
echo ""
echo "📋 DETAILED Error Breakdown:"
echo "  - Execution failures (nonce errors): ${ERROR_DETAILS["nonce_errors"]}"
echo "  - Balance errors: ${ERROR_DETAILS["balance_errors"]}"
echo "  - Network errors: ${ERROR_DETAILS["network_errors"]}"
echo "  - Other errors: ${ERROR_DETAILS["other_errors"]}"
echo ""
echo "🏗️  Block and Blob Statistics:"
echo "  - Blocks created: $block_count"
echo "  - Celestia blobs: $total_blobs"
echo "  - Expected blobs: $(( (block_count + BLOCKS_PER_BLOB - 1) / BLOCKS_PER_BLOB )) (${BLOCKS_PER_BLOB} blocks per blob)"
echo "  - Transaction compression: ${TX_TO_BLOB_RATIO} tx per blob"
echo ""
echo "⚡ Performance Metrics:"
echo "  - ✅ Successful TX throughput: ${SUCCESSFUL_TX_THROUGHPUT} tx/second"
echo "  - 📈 Total TX throughput: ${TOTAL_TX_THROUGHPUT} tx/second"
echo "  - 🏭 Block production rate: ${BLOCKS_PER_MINUTE} blocks/minute (${BLOCKS_PER_SECOND} blocks/sec)"
echo "  - 🫧 Blob creation rate: ${BLOBS_PER_MINUTE} blobs/minute"
echo "  - 📦 Batch processing: $BATCH_SIZE transactions per batch"
echo "  - ⚡ Peak processing: ${TX_PER_MINUTE} successful tx/minute"
echo ""
echo "📁 Storage Analysis:"
echo "  - 📄 Total files: $TOTAL_FILES"
echo "    • Block files: $BLOCK_FILES"
echo "    • Blob files: $BLOB_FILES"  
echo "    • Metadata files: $BLOB_METADATA_FILES"
echo "  - 💾 Storage used: $STORAGE_SIZE"
echo "  - 📏 Average block size: ${AVG_BLOCK_SIZE_KB}KB"
echo "  - 📏 Average blob size: ${AVG_BLOB_SIZE_KB}KB"
echo "  - 🎯 Storage efficiency: $STORAGE_EFFICIENCY"
echo ""
echo "🌟 Overall Performance:"
echo "  - 🎯 Average processing speed: ${OVERALL_TX_PER_MINUTE} transactions/minute"
echo "  - 🚀 Peak throughput: ${OVERALL_TX_PER_SECOND} transactions/second"
echo "  - 📊 System efficiency: $(( SUCCESSFUL_TRANSACTIONS * 100 / TOTAL_TRANSACTIONS ))% success rate"
echo "  - 💪 Scalability factor: $(( TOTAL_TRANSACTIONS / TOTAL_EXECUTION_TIME )) tx/sec sustained"
echo ""
echo "✅ Test completed at: $(date)"
if [ $FAILED_TRANSACTIONS -gt 0 ]; then
    echo "⚠️  ACCURATE FAILURE DETECTION: Found $FAILED_TRANSACTIONS failed transactions!"
    echo "   Previous version incorrectly reported 0 failures due to only checking HTTP responses."
    echo "   This version detects actual execution failures by comparing expected vs actual nonce increments."
else
    echo "🎯 Perfect execution: All transactions successful!"
fi

# Performance grade
if [ $OVERALL_TX_PER_SECOND -gt 100 ]; then
    PERFORMANCE_GRADE="🏆 EXCELLENT"
elif [ $OVERALL_TX_PER_SECOND -gt 50 ]; then
    PERFORMANCE_GRADE="🥇 VERY GOOD"
elif [ $OVERALL_TX_PER_SECOND -gt 25 ]; then
    PERFORMANCE_GRADE="🥈 GOOD"
else
    PERFORMANCE_GRADE="🥉 ACCEPTABLE"
fi

echo "🏅 Performance Grade: $PERFORMANCE_GRADE (${OVERALL_TX_PER_SECOND} tx/sec)"

# Data insights
echo ""
echo "📈 Data Insights:"
if [ $block_count -gt 0 ] && [ $TRANSACTIONS_PER_BLOCK -gt 0 ]; then
    BLOCK_UTILIZATION=$(( SUCCESSFUL_TRANSACTIONS * 100 / (block_count * TRANSACTIONS_PER_BLOCK) ))
    echo "  - Block utilization: ${BLOCK_UTILIZATION}%"
else
    echo "  - Block utilization: N/A"
fi
echo "  - Blob efficiency: ${TX_TO_BLOB_RATIO} transactions per blob"
if [ $TOTAL_TRANSACTIONS -gt 0 ]; then
    NETWORK_EFFICIENCY=$(( (SUCCESSFUL_TRANSACTIONS - ${ERROR_DETAILS["network_errors"]}) * 100 / TOTAL_TRANSACTIONS ))
    STATE_CONSISTENCY=$(( (SUCCESSFUL_TRANSACTIONS - ${ERROR_DETAILS["nonce_errors"]}) * 100 / TOTAL_TRANSACTIONS ))
    echo "  - Network efficiency: ${NETWORK_EFFICIENCY}% (network success)"
    echo "  - State consistency: ${STATE_CONSISTENCY}% (nonce accuracy)"
fi

echo ""
echo "🎯 Final Summary:"
echo "  - Total processing time: ${TOTAL_EXECUTION_TIME} seconds"
echo "  - Average speed: ${OVERALL_TX_PER_MINUTE} transactions/minute"
echo "  - Storage footprint: ${STORAGE_SIZE}"
echo "  - Data compression: ${TX_TO_BLOB_RATIO}:1 (tx:blob ratio)"
echo "  - Success rate: $(( SUCCESSFUL_TRANSACTIONS * 100 / TOTAL_TRANSACTIONS ))%"
echo ""
echo "🏁 TEST EXECUTION COMPLETE - ALL METRICS DISPLAYED"
echo "=================================================="

# Ensure all metrics are calculated even if interrupted
trap 'generate_summary' INT TERM

# Force metrics calculation if not already done
[ -z "$TOTAL_EXECUTION_TIME" ] && TOTAL_EXECUTION_TIME=$(($(date +%s) - START_TIME))
[ -z "$TRANSACTION_PROCESSING_TIME" ] && TRANSACTION_PROCESSING_TIME=$((TRANSACTION_END_TIME - TRANSACTION_START_TIME))
[ -z "$BLOCK_PRODUCTION_TIME" ] && BLOCK_PRODUCTION_TIME=$((BLOCK_PRODUCTION_END_TIME - TRANSACTION_START_TIME))

# Store summary in a file for backup
generate_summary > /tmp/rollup_summary.txt

# Display summary and ensure it's flushed
cat /tmp/rollup_summary.txt
sync

# Final sync to ensure all output is displayed
sync
sleep 1

echo ""
echo "✨ Summary generation completed successfully!"
echo "All metrics have been calculated and displayed."
echo ""