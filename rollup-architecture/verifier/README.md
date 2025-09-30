# Verifier (Settlement Layer)

This Hardhat project contains Solidity contracts to verify zk proofs (via a zkVM verifier like RiscZero) and anchor the rollup state on L1.

## Contracts
- contracts/IRiscZeroVerifier.sol
- contracts/SettlementVerifier.sol
- contracts/mocks/MockRiscZeroVerifier.sol
- contracts/Settlement.sol

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

### Deploy Settlement (anchors latest state root)
```bash
# Using our verifier and relayer
RISC0_VERIFIER_ADDRESS=0xVerifier \
RELAYER_ADDRESS=0xRelayer \
GENESIS_STATE_ROOT=0x0000000000000000000000000000000000000000000000000000000000000000 \
  npx hardhat run scripts/deploy-settlement.js --network sepolia
```

## Submit Proof
```bash
SETTLEMENT_VERIFIER_ADDRESS=0xSettlement PROOF_HEX=0x... JOURNAL_HEX=0x... \
  npx hardhat run scripts/verifyProof.js --network sepolia
```

Notes: only `RELAYER_ADDRESS` can call `verifyProof`; replay protection via `proofId`; `latestStateRoot` updates on success.

## Submit State Update (Settlement)
Phase 0 derives `newRoot = keccak256(journal)`.

```bash
SETTLEMENT_ADDRESS=0xSettlement \
EXPECTED_OLD_ROOT=0xOldRoot \
PROOF_HEX=0x... \
JOURNAL_HEX=0x... \
  npx hardhat run scripts/submit-state-update.js --network sepolia
```

Env Vars:
- `RISC0_VERIFIER_ADDRESS`: deployed zkVM verifier
- `RELAYER_ADDRESS`: authorized relayer/bridge
- `GENESIS_STATE_ROOT`: initial state root for Settlement
- `SETTLEMENT_ADDRESS`: deployed `Settlement`
- `EXPECTED_OLD_ROOT`: current canonical root (must match on-chain)
- `PROOF_HEX`, `JOURNAL_HEX`: proof and journal from prover
