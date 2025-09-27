#!/usr/bin/env bun
import { createPublicClient, http } from 'viem';
import { externalContracts } from './contracts.js';

const RPC_URL = 'https://sepolia.unichain.org';

async function main() {
  const c = externalContracts[1301];
  if (!c) throw new Error('Contracts not found for chain 1301');

  const publicClient = createPublicClient({
    transport: http(RPC_URL),
    chain: {
      id: 1301,
      name: 'Unichain Sepolia',
      nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 },
      rpcUrls: { default: { http: [RPC_URL] }, public: { http: [RPC_URL] } }
    }
  });

  console.log('=== PerpsRouter State Investigation ===');
  console.log('PerpsRouter address:', c.perpsRouter.address);

  try {
    // Get all the contract addresses stored in PerpsRouter
    const marginAccount = await publicClient.readContract({
      address: c.perpsRouter.address,
      abi: c.perpsRouter.abi,
      functionName: 'marginAccount'
    }) as `0x${string}`;

    const positionManager = await publicClient.readContract({
      address: c.perpsRouter.address,
      abi: c.perpsRouter.abi,
      functionName: 'positionManager'
    }) as `0x${string}`;

    const fundingOracle = await publicClient.readContract({
      address: c.perpsRouter.address,
      abi: c.perpsRouter.abi,
      functionName: 'fundingOracle'
    }) as `0x${string}`;

    console.log('\n=== PerpsRouter Configuration ===');
    console.log('marginAccount:', marginAccount);
    console.log('positionManager:', positionManager);
    console.log('fundingOracle:', fundingOracle);

    console.log('\n=== Our Contract Addresses ===');
    console.log('marginAccount:', c.marginAccount.address);
    console.log('positionManager:', c.positionManager.address);
    console.log('fundingOracle:', c.fundingOracle.address);

    console.log('\n=== Address Matches ===');
    console.log('marginAccount match:', marginAccount.toLowerCase() === c.marginAccount.address.toLowerCase());
    console.log('positionManager match:', positionManager.toLowerCase() === c.positionManager.address.toLowerCase());
    console.log('fundingOracle match:', fundingOracle.toLowerCase() === c.fundingOracle.address.toLowerCase());

    // Now let's check if the PositionManager that PerpsRouter knows about actually has the NFT
    console.log('\n=== NFT Ownership Check on PerpsRouter PositionManager ===');
    
    try {
      const owner = await publicClient.readContract({
        address: positionManager, // Use the address from PerpsRouter
        abi: c.positionManager.abi,
        functionName: 'ownerOf',
        args: [1n]
      }) as `0x${string}`;
      
      console.log('NFT owner on PerpsRouter.positionManager:', owner);
      console.log('Expected account:', '0xcFE743EA353d4d3D2c20C41C7d878B2cbA66DA0a');
      console.log('Match:', owner.toLowerCase() === '0xcFE743EA353d4d3D2c20C41C7d878B2cbA66DA0a'.toLowerCase());
      
    } catch (error) {
      console.log('Error checking NFT on PerpsRouter.positionManager:', error);
    }

  } catch (error) {
    console.error('Error reading PerpsRouter state:', error);
  }
}

main().catch(console.error);
