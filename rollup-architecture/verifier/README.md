# Verifier (Settlement Layer)

This Hardhat project contains Solidity contracts to verify zk proofs (via a zkVM verifier like RiscZero) and anchor the rollup state on L1.

## Contracts
- contracts/IRiscZeroVerifier.sol
- contracts/SettlementVerifier.sol
- contracts/mocks/MockRiscZeroVerifier.sol

## Setup
```bash
cd rollup-architecture/verifier
npm install
```

Create `.env` with RPC URLs, `PRIVATE_KEY`, `RELAYER_ADDRESS`, optional `RISC0_VERIFIER_ADDRESS`, and `ETHERSCAN_API_KEY`.

## Deploy
- Mock verifier (dev):
```bash
DEPLOY_MOCK_VERIFIER=1 RELAYER_ADDRESS=0xRelayer npx hardhat run scripts/deploy.js --network hardhat
```
- With official verifier:
```bash
RISC0_VERIFIER_ADDRESS=0xVerifier RELAYER_ADDRESS=0xRelayer npx hardhat run scripts/deploy.js --network sepolia
```

## Finality Checking

This verifier implements **Ethereum finality checking** to ensure proofs are only submitted after the L1 block containing rollup data is finalized. On Ethereum PoS, finality occurs ~12.8 minutes after block inclusion (2 epochs × 32 slots × 12 seconds).

### Check Finality Status

Check if a specific block (or latest) is finalized:

```bash
# Check latest block
npx hardhat run scripts/checkFinality.js --network sepolia

# Check specific block
BLOCK_TAG=12345678 npx hardhat run scripts/checkFinality.js --network sepolia

# Wait for a block to be finalized (with timeout)
WAIT_FOR_FINALITY=1 BLOCK_TAG=12345678 npx hardhat run scripts/checkFinality.js --network sepolia
```

### Submit Proof with Finality Check

The `verifyProof.js` script automatically checks finality before and after submission:

```bash
SETTLEMENT_VERIFIER_ADDRESS=0xSettlement PROOF_HEX=0x... JOURNAL_HEX=0x... \
  npx hardhat run scripts/verifyProof.js --network sepolia
```

**Options:**
- `SKIP_FINALITY_CHECK=1` - Skip finality checking (not recommended)
- `WAIT_FOR_FINALITY=1` - Wait for finality before submitting (if not finalized)

The script will:
1. Check if the latest L1 block is finalized
2. Optionally wait for finality if `WAIT_FOR_FINALITY=1`
3. Submit the proof
4. Check if the transaction block is finalized

### Understanding Finality

- **Justified**: Block has enough attestations (happens every epoch ~6.4 minutes)
- **Finalized**: Two consecutive justified epochs (happens ~12.8 minutes after inclusion)
- **Economic Security**: Reverting a finalized block requires slashing 1/3 of validators

For rollups, you should only consider state roots/proofs as **settled** after the L1 block containing them is finalized.

## Submit Proof

```bash
SETTLEMENT_VERIFIER_ADDRESS=0xSettlement PROOF_HEX=0x... JOURNAL_HEX=0x... \
  npx hardhat run scripts/verifyProof.js --network sepolia
```

**Notes:**
- Only `RELAYER_ADDRESS` can call `verifyProof`
- Replay protection via `proofId`
- `latestStateRoot` updates on success
- Finality checking is enabled by default (use `SKIP_FINALITY_CHECK=1` to disable)
