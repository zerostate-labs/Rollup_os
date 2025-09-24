const { ethers } = require("hardhat");

async function main() {
  const deployMock = process.env.DEPLOY_MOCK_VERIFIER === "1";
  let verifierAddr;

  if (deployMock) {
    const Mock = await ethers.getContractFactory("MockRiscZeroVerifier");
    const mock = await Mock.deploy();
    await mock.deployed();
    console.log("MockRiscZeroVerifier deployed:", mock.address);
    verifierAddr = mock.address;
  } else {
    verifierAddr = process.env.RISC0_VERIFIER_ADDRESS;
    if (!verifierAddr) throw new Error("Set RISC0_VERIFIER_ADDRESS or DEPLOY_MOCK_VERIFIER=1");
  }

  const relayer = process.env.RELAYER_ADDRESS;
  if (!relayer) throw new Error("Set RELAYER_ADDRESS to the authorized relayer");

  const Verifier = await ethers.getContractFactory("SettlementVerifier");
  const verifier = await Verifier.deploy(verifierAddr, relayer);
  await verifier.deployed();
  console.log("SettlementVerifier deployed:", verifier.address);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});


