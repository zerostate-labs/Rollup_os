const { ethers } = require("hardhat");
const fs = require("fs");

async function main() {
  const settlementAddr = process.env.SETTLEMENT_ADDRESS;
  const expectedOldRoot = process.env.EXPECTED_OLD_ROOT || ethers.ZeroHash;
  const proofHex = process.env.PROOF_HEX || "0x";
  const journalHex = process.env.JOURNAL_HEX || proofHex; // Phase 0 default

  if (!settlementAddr) throw new Error("Set SETTLEMENT_ADDRESS");

  // Compute proofId = keccak256(proof||journal)
  const proofId = ethers.keccak256(
    ethers.solidityPacked(["bytes", "bytes"], [proofHex, journalHex])
  );

  const Settlement = await ethers.getContractFactory("Settlement");
  const settlement = Settlement.attach(settlementAddr);

  console.log("Submitting state update to", settlementAddr);
  console.log("expectedOldRoot:", expectedOldRoot);
  console.log("proofId:", proofId);

  const tx = await settlement.submitStateUpdate(expectedOldRoot, proofHex, journalHex, proofId);
  const rcpt = await tx.wait();
  console.log("submitStateUpdate tx:", rcpt.transactionHash);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});


