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

  const tokenId = 1n;
  const account = '0xcFE743EA353d4d3D2c20C41C7d878B2cbA66DA0a';

  try {
    // Direct call to positionManager.ownerOf
    const owner = await publicClient.readContract({
      address: c.positionManager.address,
      abi: c.positionManager.abi,
      functionName: 'ownerOf',
      args: [tokenId]
    }) as `0x${string}`;

    console.log('Position Manager address:', c.positionManager.address);
    console.log('Token ID:', tokenId);
    console.log('Owner from ownerOf:', owner);
    console.log('Expected account:', account);
    console.log('Match:', owner.toLowerCase() === account.toLowerCase());
    
    // Let's also try to call this with exact same format as the contract would
    console.log('\n=== Exact comparison ===');
    console.log('owner === account:', owner === account);
    console.log('owner != account:', owner !== account);
    
    // Check if the tokens are exactly equal byte for byte
    console.log('\n=== Hex comparison ===');
    console.log('Owner hex:', owner);
    console.log('Account hex:', account);
    
  } catch (error) {
    console.error('Error calling ownerOf:', error);
  }
}

main().catch(console.error);
