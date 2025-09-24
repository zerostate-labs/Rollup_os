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

## Submit Proof
```bash
SETTLEMENT_VERIFIER_ADDRESS=0xSettlement PROOF_HEX=0x... JOURNAL_HEX=0x... \
  npx hardhat run scripts/verifyProof.js --network sepolia
```

Notes: only `RELAYER_ADDRESS` can call `verifyProof`; replay protection via `proofId`; `latestStateRoot` updates on success.
