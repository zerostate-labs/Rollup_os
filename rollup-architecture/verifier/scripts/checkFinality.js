const { ethers } = require("hardhat");

/**
 * Check if a block is finalized on Ethereum
 * @param {string} blockTag - Block number (hex string) or "latest" or "finalized"
 * @returns {Promise<{isFinalized: boolean, finalizedBlockNumber: number, targetBlockNumber: number, finalizedBlockHash: string}>}
 */
async function checkFinality(blockTag = "latest") {
  const provider = ethers.provider;

  // Get the finalized block
  let finalizedBlock;
  try {
    finalizedBlock = await provider.getBlock("finalized");
  } catch (e) {
    // Fallback for RPCs that don't support "finalized" tag (e.g. some testnets or local nodes)
    // On Ethereum PoS, 64-100 blocks is usually enough to be safe
    const latest = await provider.getBlock("latest");
    const safetyMargin = 64;
    const fallbackNumber = Math.max(0, latest.number - safetyMargin);
    finalizedBlock = await provider.getBlock(fallbackNumber);
    console.warn(`   ⚠️  RPC error fetching 'finalized' block: ${e.message}`);
    console.warn(`   ⚠️  Falling back to block ${fallbackNumber} (${safetyMargin} blocks behind latest)`);
  }

  if (!finalizedBlock) {
    throw new Error("Could not fetch finalized block or its fallback");
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
  const blocksUntilFinalized = Math.max(0, targetBlock.number - finalizedBlock.number);

  return {
    isFinalized,
    finalizedBlockNumber: finalizedBlock.number,
    targetBlockNumber: targetBlock.number,
    finalizedBlockHash: finalizedBlock.hash,
    targetBlockHash: targetBlock.hash,
    blocksUntilFinalized,
    // Add blocksBehind for compatibility but make it positive when target is newer
    blocksBehind: blocksUntilFinalized,
  };
}

/**
 * Wait for a block to be finalized
 * @param {string|number} blockNumber - Block number to wait for
 * @param {number} maxWaitSeconds - Maximum time to wait (default: 1200 = 20 minutes)
 * @param {number} pollIntervalSeconds - How often to check (default: 12 seconds)
 */
async function waitForFinality(blockNumber, maxWaitSeconds = 1200, pollIntervalSeconds = 12) {
  const startTime = Date.now();
  const maxWaitMs = maxWaitSeconds * 1000;
  const pollIntervalMs = pollIntervalSeconds * 1000;

  console.log(`Waiting for block ${blockNumber} to be finalized...`);
  console.log(`Max wait time: ${maxWaitSeconds}s (${Math.floor(maxWaitSeconds / 60)} minutes), polling every ${pollIntervalSeconds}s`);

  let checkCount = 0;
  while (Date.now() - startTime < maxWaitMs) {
    try {
      const result = await checkFinality(blockNumber);
      checkCount++;

      if (result.isFinalized) {
        console.log(`Block ${blockNumber} is now finalized!`);
        console.log(`   Finalized block: ${result.finalizedBlockNumber}`);
        console.log(`   Finalized hash: ${result.finalizedBlockHash}`);
        console.log(`   Total checks: ${checkCount}, elapsed time: ${Math.floor((Date.now() - startTime) / 1000)}s`);
        return result;
      }

      const elapsed = Math.floor((Date.now() - startTime) / 1000);
      const elapsedMinutes = Math.floor(elapsed / 60);
      const elapsedSeconds = elapsed % 60;
      console.log(`[${elapsedMinutes}m ${elapsedSeconds}s] Block ${blockNumber} not yet finalized. Current finalized: ${result.finalizedBlockNumber} (${result.blocksUntilFinalized} blocks until finalized)`);
    } catch (error) {
      console.error(`Error checking finality: ${error.message}`);
      // Continue waiting even on error (might be temporary network issue)
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
    console.log(`Blocks Until Finalized: ${result.blocksUntilFinalized}`);
    console.log(`Status: ${result.isFinalized ? "FINALIZED" : "NOT FINALIZED"}`);
    console.log("");

    if (!result.isFinalized) {
      const estimatedWaitMinutes = Math.ceil((result.blocksUntilFinalized * 12) / 60);
      console.log(`Estimated wait time: ~${estimatedWaitMinutes} minutes (${result.blocksUntilFinalized} blocks × 12s)`);
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

