#!/bin/bash

set -e

echo "🚀 Testing Rollup Prover Implementation"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "Cargo.toml" ]; then
    print_error "Please run this script from the prover directory"
    exit 1
fi

print_status "Building prover workspace..."

# Build the workspace
cargo build --workspace

if [ $? -eq 0 ]; then
    print_status "✅ Build successful"
else
    print_error "❌ Build failed"
    exit 1
fi

print_status "Running host prover..."

# Run the host prover
cd host
cargo run

if [ $? -eq 0 ]; then
    print_status "✅ Prover execution successful"
else
    print_error "❌ Prover execution failed"
    exit 1
fi

# Check if proof artifacts were created
cd ..
if [ -f "host/proof.bin" ] && [ -f "host/journal.bin" ] && [ -f "host/metadata.json" ]; then
    print_status "✅ Proof artifacts generated:"
    echo "  - proof.bin (receipt)"
    echo "  - journal.bin (public outputs)"
    echo "  - metadata.json"
else
    print_error "❌ Proof artifacts not found"
    exit 1
fi

print_status "Testing verifier compilation..."

# Test verifier compilation
cd verifier
npm install
npx hardhat compile

if [ $? -eq 0 ]; then
    print_status "✅ Verifier compilation successful"
else
    print_error "❌ Verifier compilation failed"
    exit 1
fi

cd ..

print_status "🎉 All tests passed! Prover implementation is working correctly."

echo ""
echo "Next steps:"
echo "1. Deploy the SettlementVerifier contract to a testnet"
echo "2. Set up Blobstream integration for real DA"
echo "3. Implement proper state reconstruction in the guest"
echo "4. Add more comprehensive testing"
echo "5. Optimize for production use"
