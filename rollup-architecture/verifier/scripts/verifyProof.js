const { ethers } = require("hardhat");
const { checkFinality, waitForFinality } = require("./checkFinality");

async function main() {
  const contractAddr = process.env.SETTLEMENT_VERIFIER_ADDRESS;
  if (!contractAddr) throw new Error("Set SETTLEMENT_VERIFIER_ADDRESS");

  const proofHex = process.env.PROOF_HEX || "0x";
  const journalHex = process.env.JOURNAL_HEX || "0x";
  const proofId = ethers.keccak256(ethers.solidityPacked(["bytes", "bytes"], [proofHex, journalHex]));

  // Check finality before submitting (optional - can be disabled with SKIP_FINALITY_CHECK=1)
  const skipFinalityCheck = process.env.SKIP_FINALITY_CHECK === "1";

  if (!skipFinalityCheck) {
    console.log("Checking Ethereum finality status...");
    try {
      const finalityStatus = await checkFinality("latest");
      console.log(`   Current finalized block: ${finalityStatus.finalizedBlockNumber}`);
      console.log(`   Latest block: ${finalityStatus.targetBlockNumber}`);

      if (!finalityStatus.isFinalized) {
        console.log(`Latest block is not yet finalized (${finalityStatus.blocksUntilFinalized} blocks until finalized)`);
        console.log(`Estimated wait: ~${Math.ceil((finalityStatus.blocksUntilFinalized * 12) / 60)} minutes`);

        // Optionally wait for finality if WAIT_FOR_FINALITY=1
        if (process.env.WAIT_FOR_FINALITY === "1") {
          console.log("Waiting for finality...");
          await waitForFinality(finalityStatus.targetBlockNumber);
        } else {
          console.log("Proceeding anyway (set WAIT_FOR_FINALITY=1 to wait)");
        }
      } else {
        console.log("Latest block is finalized");
      }
    } catch (error) {
      console.error(`Finality check failed: ${error.message}`);
      console.log("Proceeding with proof submission...");
    }
  }

  const Verifier = await ethers.getContractFactory("SettlementVerifier");
  const verifier = Verifier.attach(contractAddr);

  // Diagnostic: Check if current signer is authorized
  const [signer] = await ethers.getSigners();
  const relayerAddress = await verifier.relayer();
  console.log(`Current signer: ${signer.address}`);
  console.log(`Authorized relayer: ${relayerAddress}`);

  if (signer.address.toLowerCase() !== relayerAddress.toLowerCase()) {
    console.error(`\n❌ RELAYER MISMATCH: The account used to submit (${signer.address}) is not authorized.`);
    console.error(`The contract expects the relayer to be: ${relayerAddress}`);
    console.error(`Check your PRIVATE_KEY in .env and ensure it matches the RELAYER_ADDRESS used during deployment.\n`);
    process.exit(1);
  }

  console.log("\nSubmitting proof to SettlementVerifier...");
  try {
    const tx = await verifier.verifyProof(proofHex, journalHex, proofId);
    console.log(`   Transaction hash: ${tx.hash}`);
    console.log("   Waiting for confirmation...");

    const rcpt = await tx.wait();
    console.log(`Proof verified! Transaction confirmed in block ${rcpt.blockNumber}`);
    console.log(`   Transaction hash: ${rcpt.transactionHash}`);

    // Check finality of the transaction block
    if (!skipFinalityCheck) {
      console.log("\nChecking finality of transaction block...");
      try {
        const txFinality = await checkFinality(rcpt.blockNumber);
        if (txFinality.isFinalized) {
          console.log(`Transaction block ${rcpt.blockNumber} is finalized!`);
        } else {
          console.log(`Transaction block ${rcpt.blockNumber} not yet finalized (${txFinality.blocksUntilFinalized} blocks until finalized)`);
          console.log(`Estimated wait: ~${Math.ceil((txFinality.blocksUntilFinalized * 12) / 60)} minutes`);
        }
      } catch (error) {
        console.error(`Could not check transaction finality: ${error.message}`);
      }
    }
  } catch (error) {
    console.error("\n❌ Contract call failed!");
    if (error.reason) console.error(`   Reason: ${error.reason}`);
    else if (error.message) console.error(`   Message: ${error.message}`);

    if (error.data) {
      console.error(`   Error Data: ${error.data}`);
    }
    throw error;
  }
}

main().catch((e) => {
  // We don't need to print the error again here as it's caught in the try/catch blocks above
  // but we should exit with non-zero
  process.exitCode = 1;
});


