#!/usr/bin/env bun
import { createPublicClient, http } from 'viem';
import { externalContracts } from './contracts.js';

const c = externalContracts[1301];

const RPC_URL = process.env.RPC_URL || 'https://sepolia.unichain.org';

async function main() {
  const publicClient = createPublicClient({
    transport: http(RPC_URL),
    chain: {
      id: 1301,
      name: 'Unichain Sepolia',
      nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 },
      rpcUrls: { default: { http: [RPC_URL] }, public: { http: [RPC_URL] } }
    }
  });

  try {
    const positionManagerFromRouter = await publicClient.readContract({
      address: c.perpsRouter.address,
      abi: c.perpsRouter.abi,
      functionName: 'positionManager'
    }) as `0x${string}`;
    
    console.log('PositionManager from PerpsRouter:', positionManagerFromRouter);
    console.log('PositionManager in contracts.js:', c.positionManager.address);
    console.log('Match:', positionManagerFromRouter.toLowerCase() === c.positionManager.address.toLowerCase());
    
    // If they don't match, let's check ownership on the correct one
    if (positionManagerFromRouter.toLowerCase() !== c.positionManager.address.toLowerCase()) {
      console.log('\nAddresses do not match! Checking NFT ownership on correct PositionManager...');
      
      try {
        const nftOwner = await publicClient.readContract({
          address: positionManagerFromRouter,
          abi: c.positionManager.abi,
          functionName: 'ownerOf',
          args: [1n]
        }) as `0x${string}`;
        console.log('NFT owner on correct PositionManager:', nftOwner);
      } catch (error) {
        console.log('Error checking NFT ownership on correct PositionManager:', error);
      }
    }
    
  } catch (error) {
    console.error('Error:', error);
  }
}

main().catch(console.error);
