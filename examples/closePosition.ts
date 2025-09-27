import 'dotenv/config';
import { http, createWalletClient, createPublicClient, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

// Basic network config (adjust RPC via env)
const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'http://localhost:8545';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing');

async function main() {
  const tokenIdArg = process.argv[2];
  if (!tokenIdArg) throw new Error('Usage: bun run closePosition <tokenId>');
  
  const tokenId = BigInt(tokenIdArg);
  
  const c = getContracts(CHAIN_ID);
  const account = privateKeyToAccount(PK as `0x${string}`);
  
  const chain = defineChain({
    id: CHAIN_ID,
    name: 'UnichainSepolia',
    nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 },
    rpcUrls: { default: { http: [RPC_URL] }, public: { http: [RPC_URL] } }
  });

  const walletClient = createWalletClient({
    account,
    transport: http(RPC_URL),
    chain
  });

  const publicClient = createPublicClient({
    transport: http(RPC_URL),
    chain
  });

  console.log('Account:', account.address);
  console.log(`Closing position with token ID: ${tokenId}`);

  // Check NFT ownership first
  try {
    const nftOwner = await publicClient.readContract({
      address: c.positionManager.address,
      abi: c.positionManager.abi,
      functionName: 'ownerOf',
      args: [tokenId]
    }) as `0x${string}`;
    console.log(`NFT owner: ${nftOwner}`);
    
    if (nftOwner.toLowerCase() !== account.address.toLowerCase()) {
      console.log(`Error: Account ${account.address} does not own NFT token ${tokenId}`);
      console.log(`NFT is owned by: ${nftOwner}`);
      return;
    }
  } catch (error) {
    console.log(`Error checking NFT ownership: ${error}`);
    return;
  }

  // Get position details before closing
  try {
    const position = await publicClient.readContract({
      address: c.positionManager.address,
      abi: c.positionManager.abi,
      functionName: 'getPosition',
      args: [tokenId]
    }) as any;
    
    console.log('Current position details:');
    console.log('- Market ID:', position.marketId);
    console.log('- Size (base):', position.sizeBase.toString());
    console.log('- Entry price:', position.entryPrice.toString());
    console.log('- Margin:', position.margin.toString());
    console.log('- Direction:', position.sizeBase > 0n ? 'LONG' : 'SHORT');
    
    // Check position owner
    if (position.owner.toLowerCase() !== account.address.toLowerCase()) {
      throw new Error(`Position ${tokenId} is not owned by ${account.address}`);
    }
    
  } catch (error) {
    console.log('Failed to get position details:', error);
    return;
  }

  // Close position via PerpsRouter
  try {
    console.log('Closing position...');
    
    // Prepare close position parameters
    const closePositionParams = {
      tokenId: tokenId,
      sizeBps: 10000n, // 100% (close entire position)
      slippageBps: 100n, // 1% slippage tolerance
      deadline: BigInt(Math.floor(Date.now() / 1000) + 300) // 5 minutes from now
    };
    
    const closeTx = await walletClient.writeContract({
      address: c.perpsRouter.address,
      abi: c.perpsRouter.abi,
      functionName: 'closePosition',
      args: [closePositionParams]
    });
    
    console.log(`Close position tx hash: ${closeTx}`);
    
    // Wait for transaction confirmation
    const receipt = await publicClient.waitForTransactionReceipt({ hash: closeTx });
    console.log(`Transaction confirmed in block: ${receipt.blockNumber}`);
    
    // Check if position still exists (should be removed or have zero size)
    try {
      const finalPosition = await publicClient.readContract({
        address: c.positionManager.address,
        abi: c.positionManager.abi,
        functionName: 'getPosition',
        args: [tokenId]
      }) as any;
      
      if (finalPosition.sizeBase === 0n) {
        console.log('✅ Position successfully closed (size = 0)');
      } else {
        console.log('⚠️ Position size after closing:', finalPosition.sizeBase.toString());
      }
    } catch (error) {
      console.log('Position may have been removed or burned after closing');
    }
    
    // Check margin balance after closing
    try {
      const marginBalance = await publicClient.readContract({
        address: c.marginAccount.address,
        abi: c.marginAccount.abi,
        functionName: 'getMarginBalance',
        args: [account.address]
      });
      console.log(`Margin balance after closing: ${marginBalance} USDC (wei)`);
    } catch (error) {
      console.log('Could not fetch margin balance:', error);
    }
    
  } catch (error) {
    console.log('Failed to close position:', error);
  }
}

main().catch(console.error);
