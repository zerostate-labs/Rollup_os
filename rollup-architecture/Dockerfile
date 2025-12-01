FROM ubuntu:22.04

# Prevent interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Update PATH to include Go and Cargo binaries
ENV PATH="/root/.cargo/bin:/usr/local/go/bin:/root/go/bin:${PATH}"

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    pkg-config \
    libssl-dev \
    python3 \
    python3-pip \
    jq \
    vim \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Go (v1.23.3)
RUN wget https://go.dev/dl/go1.23.3.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.23.3.linux-amd64.tar.gz && \
    rm go1.23.3.linux-amd64.tar.gz

# Install Rust (Latest Stable)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# Install Node.js (v20 LTS)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs

# Install Celestia CLI tools
# We install both appd and node as per README instructions
RUN go install github.com/celestiaorg/celestia-app/cmd/celestia-appd@latest && \
    go install github.com/celestiaorg/celestia-node/cmd/celestia@latest

# Set working directory
WORKDIR /app

# Copy the codebase
COPY . .

# Patch the script to replace hardcoded WSL paths with the container path (/app)
# This ensures the script runs correctly inside Docker without modifying the source file on the host permanently
RUN sed -i 's|/mnt/e/zerostate_rollup/rollup-architecture|/app|g' scripts/complete_rollup_test.sh

# Install Verifier dependencies (Hardhat, etc.)
RUN cd verifier && npm install

# Pre-build Rollup Node to speed up execution
# We build with the 'prover' feature as used in the script
RUN cd rollup-node && cargo build --release --features prover

# Make the test script executable
RUN chmod +x scripts/complete_rollup_test.sh

# Default command to run the test script
CMD ["./scripts/complete_rollup_test.sh"]
