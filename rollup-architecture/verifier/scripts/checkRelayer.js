const { ethers } = require("hardhat");

async function main() {
    const contractAddr = "0xFEE73AD2904b90C53Eb5979581c975BaBFa836ca";
    const Verifier = await ethers.getContractFactory("SettlementVerifier");
    const verifier = Verifier.attach(contractAddr);

    try {
        const relayer = await verifier.relayer();
        console.log("Relayer set in contract:", relayer);

        const [signer] = await ethers.getSigners();
        console.log("Current signer address:", signer.address);

        if (relayer.toLowerCase() === signer.address.toLowerCase()) {
            console.log("Signer IS the relayer. Authorized! ✅");
        } else {
            console.log("Signer IS NOT the relayer. Unauthorized! ❌");
        }
    } catch (error) {
        console.error("Error reading relayer:", error.message);
    }
}

main().catch(console.error);
