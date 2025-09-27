#!/usr/bin/env bun
import { createPublicClient, createWalletClient, http, parseEther, formatEther } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { externalContracts } from './contracts.js';

const RPC_URL = process.env.RPC_URL || 'https://sepolia.unichain.org';
const PRIVATE_KEY = process.env.PRIVATE_KEY as `0x${string}`;
const tokenId = BigInt(process.argv[2] || '1');

const c = externalContracts[1301];
if (!c) throw new Error('Contracts not found for chain 1301');

async function main() {
  const account = privateKeyToAccount(PRIVATE_KEY);
  
  const chain = {
    id: 1301,
    name: 'Unichain Sepolia',
    nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 },
    rpcUrls: { default: { http: [RPC_URL] }, public: { http: [RPC_URL] } }
  };

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
  console.log(`Testing closePosition call for token ID: ${tokenId}`);

  try {
    // First, let's simulate the call to see what specific error we get
    console.log('\n=== Simulating closePosition call ===');
    
    const closePositionParams = {
      tokenId: tokenId,
      sizeBps: 10000n, // 100% (close entire position)
      slippageBps: 100n, // 1% slippage tolerance
      deadline: BigInt(Math.floor(Date.now() / 1000) + 300) // 5 minutes from now
    };

    const simulationResult = await publicClient.simulateContract({
      address: c.perpsRouter.address,
      abi: c.perpsRouter.abi,
      functionName: 'closePosition',
      args: [closePositionParams],
      account: account.address
    });
    
    console.log('Simulation successful:', simulationResult);
    
  } catch (error: any) {
    console.log('Simulation failed:', error.message);
    
    if (error.message?.includes('NotPositionOwner')) {
      console.log('\n=== Debugging NotPositionOwner error ===');
      
      // Check current NFT owner
      const nftOwner = await publicClient.readContract({
        address: c.positionManager.address,
        abi: c.positionManager.abi,
        functionName: 'ownerOf',
        args: [tokenId]
      }) as `0x${string}`;
      
      console.log('NFT owner:', nftOwner);
      console.log('Account address:', account.address);
      console.log('Address match:', nftOwner.toLowerCase() === account.address.toLowerCase());
      
      // Let's also check if the token exists
      try {
        const position = await publicClient.readContract({
          address: c.positionManager.address,
          abi: c.positionManager.abi,
          functionName: 'getPosition',
          args: [tokenId]
        });
        console.log('Position exists:', !!position);
      } catch (posError) {
        console.log('Position does not exist or error getting position:', posError);
      }
      
      // Check if the PerpsRouter has the correct PositionManager address
      const routerPositionManager = await publicClient.readContract({
        address: c.perpsRouter.address,
        abi: c.perpsRouter.abi,
        functionName: 'positionManager'
      }) as `0x${string}`;
      
      console.log('PerpsRouter.positionManager:', routerPositionManager);
      console.log('Our PositionManager address:', c.positionManager.address);
      console.log('PositionManager addresses match:', routerPositionManager.toLowerCase() === c.positionManager.address.toLowerCase());
    }
  }
}

main().catch(console.error);
