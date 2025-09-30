const { ethers } = require("hardhat");

async function main() {
  const verifierAddr = process.env.RISC0_VERIFIER_ADDRESS;
  const relayer = process.env.RELAYER_ADDRESS;
  const genesis = process.env.GENESIS_STATE_ROOT || ethers.ZeroHash;
  if (!verifierAddr) throw new Error("Set RISC0_VERIFIER_ADDRESS");
  if (!relayer) throw new Error("Set RELAYER_ADDRESS");

  const relayerAddress = ethers.getAddress(relayer);

  const Settlement = await ethers.getContractFactory("Settlement");
  const settlement = await Settlement.deploy(verifierAddr, relayerAddress, genesis);
  await settlement.waitForDeployment();

  console.log("Settlement deployed:", await settlement.getAddress());
  console.log("  verifier:", verifierAddr);
  console.log("  relayer:", relayerAddress);
  console.log("  genesis:", genesis);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});


