#!/bin/bash

# Rollup Node Integration Test
# Tests transaction processing and block production workflow

set -e

# Configuration
TRANSACTIONS_PER_BLOCK=100  # 100 transactions per block
TOTAL_TRANSACTIONS=500      # Total transactions to submit (will create 5 blocks: 100, 100, 100, 100, 100)

echo "Starting Rollup Node Integration Test..."
echo "========================================"
echo "Configuration:"
echo "  Transactions per block: $TRANSACTIONS_PER_BLOCK"
echo "  Total transactions: $TOTAL_TRANSACTIONS"
echo "  Expected blocks: $(( (TOTAL_TRANSACTIONS + TRANSACTIONS_PER_BLOCK - 1) / TRANSACTIONS_PER_BLOCK ))"
echo ""

# Start the rollup node in background
echo "Starting rollup node..."
cargo run &
NODE_PID=$!

# Wait for node to start
sleep 3

# Verify node is running
if ! curl -s http://localhost:8080/state/alice > /dev/null; then
    echo "Error: Rollup node failed to start"
    kill $NODE_PID 2>/dev/null || true
    exit 1
fi

echo "Rollup node started successfully"

# Configure transactions per block
echo ""
echo "Configuring transactions per block..."
curl -s -X POST http://localhost:8080/config/tx-per-block \
    -H "Content-Type: application/json" \
    -d "{\"transactions_per_block\": $TRANSACTIONS_PER_BLOCK}" | jq -r '"Configuration: " + .message + " (tx per block: " + (.transactions_per_block | tostring) + ")"'

# Display initial account balances
echo ""
echo "Initial Account Balances:"
echo "-------------------------"
curl -s http://localhost:8080/state/alice | jq -r '"Alice:   " + .balance'
curl -s http://localhost:8080/state/bob | jq -r '"Bob:     " + .balance'
curl -s http://localhost:8080/state/charlie | jq -r '"Charlie: " + .balance'
curl -s http://localhost:8080/state/diana | jq -r '"Diana:   " + .balance'

# Submit transactions and produce blocks automatically
echo ""
echo "Processing transactions and producing blocks..."
echo "=============================================="

block_number=1
tx_count=0

for i in $(seq 0 $((TOTAL_TRANSACTIONS - 1))); do
    # Generate transaction
    case $((i % 4)) in
        0) from="alice"; to="bob"; amount=$((100 + i * 10)); ;;
        1) from="bob"; to="charlie"; amount=$((50 + i * 5)); ;;
        2) from="charlie"; to="diana"; amount=$((75 + i * 8)); ;;
        3) from="diana"; to="alice"; amount=$((200 + i * 15)); ;;
    esac
    
    # Submit transaction
    curl -s -X POST http://localhost:8080/tx \
        -H "Content-Type: application/json" \
        -d "{\"from\": \"$from\", \"to\": \"$to\", \"amount\": \"$amount\", \"nonce\": $((i / 4))}" > /dev/null
    
    echo "  Submitted: $from → $to ($amount)"
    tx_count=$((tx_count + 1))
    
    # Check if we should produce a block
    if [ $((tx_count % TRANSACTIONS_PER_BLOCK)) -eq 0 ]; then
        echo ""
        echo "Producing Block $block_number..."
        echo "-------------------------------"
        
        block_response=$(curl -s -X POST http://localhost:8080/block/produce)
        echo "$block_response" | jq -r '"Block Number: " + (.block_number | tostring)'
        echo "$block_response" | jq -r '"Blob Path: " + .blob_path'
        echo "$block_response" | jq -r '"Blob Hash: " + .blob_hash'
        
        block_number=$((block_number + 1))
        echo ""
    fi
done

# Check if there are remaining transactions and produce final block if needed
echo ""
echo "Checking for remaining transactions..."
remaining_response=$(curl -s -X POST http://localhost:8080/block/produce)
if echo "$remaining_response" | jq -e '.error' > /dev/null; then
    echo "No remaining transactions to produce final block"
else
    echo "Producing final block with remaining transactions..."
    echo "------------------------------------------------"
    echo "$remaining_response" | jq -r '"Block Number: " + (.block_number | tostring)'
    echo "$remaining_response" | jq -r '"Blob Path: " + .blob_path'
    echo "$remaining_response" | jq -r '"Blob Hash: " + .blob_hash'
fi

# Display final account balances
echo ""
echo "Final Account Balances:"
echo "----------------------"
curl -s http://localhost:8080/state/alice | jq -r '"Alice:   " + .balance'
curl -s http://localhost:8080/state/bob | jq -r '"Bob:     " + .balance'
curl -s http://localhost:8080/state/charlie | jq -r '"Charlie: " + .balance'
curl -s http://localhost:8080/state/diana | jq -r '"Diana:   " + .balance'

# Verify blocks were written to local-da
echo ""
echo "Verifying Data Availability:"
echo "---------------------------"
if [ -d "local-da" ]; then
    block_count=$(ls local-da/block_*.json 2>/dev/null | wc -l)
    echo "Blocks written to local-da: $block_count"
    if [ $block_count -gt 0 ]; then
        echo "Block files:"
        ls -la local-da/block_*.json 2>/dev/null | while read line; do
            echo "  $line"
        done
    fi
else
    echo "Warning: local-da directory not found"
fi

# Cleanup
echo ""
echo "Cleaning up..."
kill $NODE_PID
wait $NODE_PID 2>/dev/null

echo ""
echo "Rollup Node Integration Test completed successfully!"
echo "=================================================="
