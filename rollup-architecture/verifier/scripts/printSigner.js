const { ethers } = require("hardhat");

async function main() {
    const [signer] = await ethers.getSigners();
    console.log("Hardhat Signer Address:", signer.address);
}

main().catch(console.error);
