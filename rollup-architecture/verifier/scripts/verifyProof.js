const { ethers } = require("hardhat");

async function main() {
  const contractAddr = process.env.SETTLEMENT_VERIFIER_ADDRESS;
  if (!contractAddr) throw new Error("Set SETTLEMENT_VERIFIER_ADDRESS");

  const proofHex = process.env.PROOF_HEX || "0x";
  const journalHex = process.env.JOURNAL_HEX || "0x";
  const proofId = ethers.utils.keccak256(ethers.utils.solidityPack(["bytes", "bytes"], [proofHex, journalHex]));

  const Verifier = await ethers.getContractFactory("SettlementVerifier");
  const verifier = Verifier.attach(contractAddr);

  const tx = await verifier.verifyProof(proofHex, journalHex, proofId);
  const rcpt = await tx.wait();
  console.log("verifyProof tx:", rcpt.transactionHash);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});


