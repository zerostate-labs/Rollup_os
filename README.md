# 🏗️ Rollup Architecture – State Machine (Build Anything. Prove Everything. Scale Everywhere)
# Plug. Play. Prove. The Next-Gen Rollup OS

A modular **TowerABCI-based rollup** architecture featuring:
- **Ethereum Settlement** with smart contracts
- **Celestia Data Availability**
- **ZK Proof System** using SP1/RiscZero
- **Oracle Integration** for external data feeds
- **Bridge Layer** for cross-chain commitments
- **Developer Tooling** for local, testnet, and mainnet deployments

---
## 📂 Project Structure

```plaintext
rollup-architecture/
│
├── docs/                      # Documentation
│   ├── architecture.md        # High-level architecture overview
│   ├── phases.md              # Phase 0 → Phase 2 plan
│   ├── api-spec.md            # API endpoints / gRPC / ABCI spec
│   ├── proof-system.md        # ZK proof circuits documentation
│   └── deployment-guide.md    # How to deploy locally & on testnet
│
├── contracts/                 # Ethereum smart contracts
│   ├── src/
│   │   ├── Settlement.sol     # Verifies proofs & updates state
│   │   ├── BlobstreamVerifier.sol # Handles Celestia → Ethereum bridge data
│   │   ├── interfaces/        # Contract interfaces
│   │   └── libs/              # Shared libraries
│   ├── test/                  # Hardhat/Foundry tests
│   ├── deploy/                # Deployment scripts
│   └── hardhat.config.js      # Config for local/testnet deployments
│
├── rollup-node/               # TowerABCI rollup node
│   ├── cmd/
│   │   └── rollupd/           # Main executable
│   ├── state/                 # State machine logic
│   ├── abci/                  # ABCI handlers
│   ├── da_publisher/          # Sends data to Celestia
│   ├── oracle_adapter/        # Pulls & packages oracle data
│   ├── proof_adapter/         # Communicates with ZK prover service
│   └── config/                # Node config & genesis
│
├── prover/                    # ZK proof generation
│   ├── circuits/              # SP1/RiscZero circuit definitions
│   ├── executor/              # Execution replayer
│   ├── verifier/              # Proof verifier logic (off-chain)
│   └── scripts/               # Scripts to run proofs
│
├── bridge/                    # Celestia → Ethereum bridge
│   ├── blobstream-client/     # Consumes Celestia blobs & produces proofs
│   ├── relayer/               # Pushes proofs + commitments to Ethereum
│   └── mock/                  # Phase 0 mock bridge
│
├── tools/                     # Dev tooling
│   ├── cli/                   # Command-line tool for monitoring & debugging
│   ├── proof-explorer/        # Web UI to inspect proofs & blobs
│   └── sdk/                   # JS/Go SDK for dApp developers
│
├── deployments/               # Deployment configs
│   ├── localnet/              # Local docker-compose setup
│   ├── testnet/               # Testnet configs
│   └── mainnet/               # Production configs
│
├── scripts/                   # Utility scripts
│   ├── start-local.sh         # Run local Celestia + Ethereum + rollup
│   ├── deploy-contracts.sh    # Deploy smart contracts
│   └── generate-proof.sh      # Run proof generation
│
├── .github/                   # GitHub Actions CI/CD
│   ├── workflows/
│   │   ├── test.yml           # Run tests
│   │   ├── lint.yml           # Linting
│   │   └── deploy.yml         # Deploy to testnet
│
├── docker-compose.yml         # Local testnet setup
├── go.mod                     # Go dependencies (TowerABCI)
├── package.json               # JS dependencies (tooling/UI)
├── README.md                  # Project overview
└── LICENSE
