const { ethers } = require("hardhat");

/**
 * Check if a block is finalized on Ethereum
 * @param {string} blockTag - Block number (hex string) or "latest" or "finalized"
 * @returns {Promise<{isFinalized: boolean, finalizedBlockNumber: number, targetBlockNumber: number, finalizedBlockHash: string}>}
 */
async function checkFinality(blockTag = "latest") {
  const provider = ethers.provider;
  
  // Get the finalized block
  const finalizedBlock = await provider.getBlock("finalized");
  if (!finalizedBlock) {
    throw new Error("Could not fetch finalized block");
  }
  
  // Get the target block
  let targetBlock;
  if (blockTag === "latest" || blockTag === "finalized") {
    targetBlock = await provider.getBlock(blockTag);
  } else {
    // Convert hex string to number if needed
    const blockNumber = typeof blockTag === "string" && blockTag.startsWith("0x")
      ? parseInt(blockTag, 16)
      : parseInt(blockTag);
    targetBlock = await provider.getBlock(blockNumber);
  }
  
  if (!targetBlock) {
    throw new Error(`Could not fetch block ${blockTag}`);
  }
  
  const isFinalized = targetBlock.number <= finalizedBlock.number;
  
  return {
    isFinalized,
    finalizedBlockNumber: finalizedBlock.number,
    targetBlockNumber: targetBlock.number,
    finalizedBlockHash: finalizedBlock.hash,
    targetBlockHash: targetBlock.hash,
    blocksBehind: finalizedBlock.number - targetBlock.number,
  };
}

/**
 * Wait for a block to be finalized
 * @param {string|number} blockNumber - Block number to wait for
 * @param {number} maxWaitSeconds - Maximum time to wait (default: 900 = 15 minutes)
 * @param {number} pollIntervalSeconds - How often to check (default: 12 seconds)
 */
async function waitForFinality(blockNumber, maxWaitSeconds = 900, pollIntervalSeconds = 12) {
  const startTime = Date.now();
  const maxWaitMs = maxWaitSeconds * 1000;
  const pollIntervalMs = pollIntervalSeconds * 1000;
  
  console.log(`Waiting for block ${blockNumber} to be finalized...`);
  console.log(`Max wait time: ${maxWaitSeconds}s, polling every ${pollIntervalSeconds}s`);
  
  while (Date.now() - startTime < maxWaitMs) {
    try {
      const result = await checkFinality(blockNumber);
      
      if (result.isFinalized) {
        console.log(`Block ${blockNumber} is now finalized!`);
        console.log(`   Finalized block: ${result.finalizedBlockNumber}`);
        console.log(`   Finalized hash: ${result.finalizedBlockHash}`);
        return result;
      }
      
      console.log(`Block ${blockNumber} not yet finalized. Current finalized: ${result.finalizedBlockNumber} (${result.blocksBehind} blocks behind)`);
    } catch (error) {
      console.error(`Error checking finality: ${error.message}`);
    }
    
    await new Promise(resolve => setTimeout(resolve, pollIntervalMs));
  }
  
  throw new Error(`Timeout: Block ${blockNumber} did not finalize within ${maxWaitSeconds} seconds`);
}

async function main() {
  const blockTag = process.env.BLOCK_TAG || "latest";
  const waitMode = process.env.WAIT_FOR_FINALITY === "1";
  
  if (waitMode) {
    const blockNumber = blockTag === "latest" 
      ? (await ethers.provider.getBlock("latest")).number
      : parseInt(blockTag);
    await waitForFinality(blockNumber);
  } else {
    const result = await checkFinality(blockTag);
    
    console.log("\nFinality Check Results:");
    console.log("==========================");
    console.log(`Target Block: ${result.targetBlockNumber}`);
    console.log(`Target Hash:  ${result.targetBlockHash}`);
    console.log(`Finalized Block: ${result.finalizedBlockNumber}`);
    console.log(`Finalized Hash:  ${result.finalizedBlockHash}`);
    console.log(`Blocks Behind: ${result.blocksBehind}`);
    console.log(`Status: ${result.isFinalized ? "FINALIZED" : "NOT FINALIZED"}`);
    console.log("");
    
    if (!result.isFinalized) {
      const estimatedWaitMinutes = Math.ceil((result.blocksBehind * 12) / 60);
      console.log(`Estimated wait time: ~${estimatedWaitMinutes} minutes (${result.blocksBehind} blocks × 12s)`);
    }
    
    process.exitCode = result.isFinalized ? 0 : 1;
  }
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e);
    process.exitCode = 1;
  });
}

module.exports = { checkFinality, waitForFinality };

