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
        console.log(`Latest block is not yet finalized (${finalityStatus.blocksBehind} blocks behind)`);
        console.log(`Estimated wait: ~${Math.ceil((finalityStatus.blocksBehind * 12) / 60)} minutes`);
        
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

  console.log("\nSubmitting proof to SettlementVerifier...");
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
        console.log(`Transaction block ${rcpt.blockNumber} not yet finalized (${txFinality.blocksBehind} blocks behind)`);
        console.log(`Estimated wait: ~${Math.ceil((txFinality.blocksBehind * 12) / 60)} minutes`);
      }
    } catch (error) {
      console.error(`Could not check transaction finality: ${error.message}`);
    }
  }
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});


