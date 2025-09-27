const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  const contractAddr = "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512";
  
  const proofPath = path.join(__dirname, "../../rollup-node/local-da/proof_block_1.hex");
  const proofHex = "0x" + fs.readFileSync(proofPath, "utf8").trim();
  
  const journalHex = proofHex; // simplified approach, need to change this later
  
  // keccak256 of proof + journal
  const proofId = ethers.keccak256(ethers.solidityPacked(["bytes", "bytes"], [proofHex, journalHex]));
  
  console.log("Contract Address:", contractAddr);
  console.log("Proof Hex:", proofHex.substring(0, 50) + "...");
  console.log("Journal Hex:", journalHex.substring(0, 50) + "...");
  console.log("Proof ID:", proofId);
  
  const Verifier = await ethers.getContractFactory("SettlementVerifier");
  const verifier = Verifier.attach(contractAddr);
  
  console.log("Submitting proof for verification...");
  
  try {
    const tx = await verifier.verifyProof(proofHex, journalHex, proofId);
    const rcpt = await tx.wait();
    console.log("Proof verified successfully!");
    console.log("Transaction hash:", rcpt.transactionHash);
    
    // Get the latest state root
    try {
      const latestStateRoot = await verifier.latestStateRoot();
      console.log("Latest state root:", latestStateRoot);
    } catch (e) {
      console.log("Note: Could not read state root (this is normal for mock verifier)");
    }
    
  } catch (error) {
    console.error("❌ Proof verification failed:", error.message);
  }
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
