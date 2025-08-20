#!/bin/bash

# Rollup Node Integration Test with Blob Creation
# Tests transaction processing, block production, and blob creation workflow

set -e

# Configuration
TRANSACTIONS_PER_BLOCK=100  # 100 transactions per block
BLOCKS_PER_BLOB=2          # 2 blocks per blob
TOTAL_TRANSACTIONS=500     # Total transactions to submit (will create 5 blocks)

echo "Starting Rollup Node Integration Test with Blob Creation..."
echo "=========================================================="
echo "Configuration:"
echo "  Transactions per block: $TRANSACTIONS_PER_BLOCK"
echo "  Blocks per blob: $BLOCKS_PER_BLOB"
echo "  Total transactions: $TOTAL_TRANSACTIONS"
echo "  Expected blocks: $(( (TOTAL_TRANSACTIONS + TRANSACTIONS_PER_BLOCK - 1) / TRANSACTIONS_PER_BLOCK ))"
echo "  Expected blobs: $(( (5 + BLOCKS_PER_BLOB - 1) / BLOCKS_PER_BLOB )) (2 blocks + 2 blocks + 1 block)"
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

# Wait for node to start and verify it's running
echo "Waiting for rollup node to start..."
for i in {1..10}; do
    if curl -s http://localhost:8080/state/alice > /dev/null 2>&1; then
        echo "Rollup node is ready!"
        break
    fi
    if [ $i -eq 10 ]; then
        echo "Error: Rollup node failed to start after 10 attempts"
        exit 1
    fi
    echo "Attempt $i/10: Waiting for rollup node..."
    sleep 2
done

echo "Rollup node started successfully"

# Configure transactions per block
echo ""
echo "Configuring transactions per block..."
curl -s -X POST http://localhost:8080/config/tx-per-block \
    -H "Content-Type: application/json" \
    -d "{\"transactions_per_block\": $TRANSACTIONS_PER_BLOCK}" | jq -r '"Configuration: " + .message + " (tx per block: " + (.transactions_per_block | tostring) + ")"'

# Configure blocks per blob
echo ""
echo "Configuring blocks per blob..."
curl -s -X POST http://localhost:8080/config/blocks-per-blob \
    -H "Content-Type: application/json" \
    -d "{\"blocks_per_blob\": $BLOCKS_PER_BLOB}" | jq -r '"Blob Configuration: " + .message + " (blocks per blob: " + (.blocks_per_blob | tostring) + ")"'

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
echo "Verifying Block Data Availability:"
echo "---------------------------------"
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

# Test Celestia Blob Creation from Storage
echo ""
echo "Testing Celestia Blob Creation from Storage..."
echo "============================================="

# Note: Skipping memory-based blob creation to test only storage-based workflow
echo ""
echo "Note: Skipping memory-based blob creation. Testing only storage-based blob creation."

# Test loading blocks from storage and creating blobs
echo ""
echo "Testing Block Loading and Blob Creation from Storage..."
echo "====================================================="

# First, let's load all blocks from storage
echo ""
echo "Loading all blocks (1, 2, 3, 4, 5) from storage..."
load_response=$(curl -s -X POST http://localhost:8080/blob/load-blocks \
    -H "Content-Type: application/json" \
    -d '{"block_numbers": [1, 2, 3, 4, 5]}')

echo "$load_response" | jq -r '"Loaded blocks: " + (.loaded_blocks | tostring) + " / " + (.total_blocks_requested | tostring)'

if [ "$(echo "$load_response" | jq -r '.errors | length')" -gt 0 ]; then
    echo "Errors during loading:"
    echo "$load_response" | jq -r '.errors[]'
fi

# Create blobs from loaded blocks
echo ""
echo "Creating blobs from loaded blocks..."
create_response=$(curl -s -X POST http://localhost:8080/blob/create-from-blocks)

if echo "$create_response" | jq -e '.error' > /dev/null; then
    echo "Error creating blobs from loaded blocks:"
    echo "$create_response" | jq -r '.error'
else
    echo "Blob creation from loaded blocks successful!"
    echo "$create_response" | jq -r '"Created blobs: " + (.created_blobs | tostring)'
    echo "$create_response" | jq -r '"Blocks processed: " + (.blocks_processed | tostring)'
    echo "$create_response" | jq -r '"Total transactions: " + (.total_transactions | tostring)'
fi

# Final verification
echo ""
echo "Final Blob Listing:"
echo "==================="
final_list_response=$(curl -s -X GET http://localhost:8080/blob/list)
echo "$final_list_response" | jq -r '"Total blobs created: " + (.total | tostring)'

echo ""
echo "Final Directory Structure:"
echo "========================="
if [ -d "local-da" ]; then
    echo "local-da directory contents:"
    find local-da -type f | sort | while read file; do
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "unknown")
        echo "  $file ($size bytes)"
    done
else
    echo "local-da directory not found"
fi

echo ""
echo "Rollup Node Integration Test with Blob Creation completed successfully!"
echo "====================================================================="
echo ""
echo "Summary:"
echo "  - Processed $TOTAL_TRANSACTIONS transactions"
echo "  - Created $(ls local-da/block_*.json 2>/dev/null | wc -l) blocks"
echo "  - Generated $(echo "$final_list_response" | jq -r '.total') Celestia blobs"
echo "  - Expected blob distribution: 2+2+1 blocks per blob = 3 blobs total"
