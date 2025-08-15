#!/bin/bash

# Test script for rollup node
echo "Testing Rollup Node..."

# Start the rollup node in background
echo "Starting rollup node..."
cargo run &
NODE_PID=$!

# Wait for node to start
sleep 3

# Test 1: Check initial state
echo "Test 1: Checking initial state..."
curl -s http://localhost:8080/state/alice | jq .
curl -s http://localhost:8080/state/bob | jq .

# Test 2: Submit a transaction
echo "Test 2: Submitting transaction..."
curl -X POST http://localhost:8080/tx \
  -H "Content-Type: application/json" \
  -d '{"from": "alice", "to": "bob", "amount": "100", "nonce": 0}' | jq .
curl -X POST http://localhost:8080/tx \
  -H "Content-Type: application/json" \
  -d '{"from": "alice", "to": "bob", "amount": "50", "nonce": 1}' | jq .
curl -X POST http://localhost:8080/tx \
  -H "Content-Type: application/json" \
  -d '{"from": "alice", "to": "bob", "amount": "70", "nonce": 2}' | jq .
curl -X POST http://localhost:8080/tx \
  -H "Content-Type: application/json" \
  -d '{"from": "alice", "to": "bob", "amount": "100", "nonce": 3}' | jq .
curl -X POST http://localhost:8080/tx \
  -H "Content-Type: application/json" \
  -d '{"from": "alice", "to": "bob", "amount": "100", "nonce": 4}' | jq .
curl -X POST http://localhost:8080/tx \
  -H "Content-Type: application/json" \
  -d '{"from": "alice", "to": "bob", "amount": "100", "nonce": 5}' | jq .
curl -X POST http://localhost:8080/tx \
  -H "Content-Type: application/json" \
  -d '{"from": "bob", "to": "alice", "amount": "100", "nonce": 6}' | jq .
curl -X POST http://localhost:8080/tx \
  -H "Content-Type: application/json" \
  -d '{"from": "alice", "to": "bob", "amount": "100", "nonce": 7}' | jq .
curl -X POST http://localhost:8080/tx \
  -H "Content-Type: application/json" \
  -d '{"from": "bob", "to": "alice", "amount": "100", "nonce": 8}' | jq .

# Test 3: Produce a block
echo "Test 3: Producing block..."
curl -X POST http://localhost:8080/block/produce | jq .

# Test 4: Check state after transaction
echo "Test 4: Checking state after transaction..."
curl -s http://localhost:8080/state/alice | jq .
curl -s http://localhost:8080/state/bob | jq .

# Test 5: Submit another transaction
echo "Test 5: Submitting another transaction..."
curl -X POST http://localhost:8080/tx \
  -H "Content-Type: application/json" \
  -d '{"from": "bob", "to": "alice", "amount": "50", "nonce": 9}' | jq .

# Test 6: Produce another block
echo "Test 6: Producing another block..."
curl -X POST http://localhost:8080/block/produce | jq .

# Test 7: Check final state
echo "Test 7: Checking final state..."
curl -s http://localhost:8080/state/alice | jq .
curl -s http://localhost:8080/state/bob | jq .

# Cleanup
echo "Cleaning up..."
kill $NODE_PID
wait $NODE_PID 2>/dev/null

echo "Test completed!"
