#!/usr/bin/env bun
import { createPublicClient, createWalletClient, http } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { externalContracts } from './contracts.js';

const RPC_URL = 'https://sepolia.unichain.org';
const PRIVATE_KEY = '0xcf43b326c9b11208da2d1f0d36b97a54af487e07ff56f22536bfa29a1ba35644' as `0x${string}`;

async function main() {
  const c = externalContracts[1301];
  if (!c) throw new Error('Contracts not found for chain 1301');

  const account = privateKeyToAccount(PRIVATE_KEY);
  
  const chain = {
    id: 1301,
    name: 'Unichain Sepolia',
    nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 },
    rpcUrls: { default: { http: [RPC_URL] }, public: { http: [RPC_URL] } }
  };

  const publicClient = createPublicClient({
    transport: http(RPC_URL),
    chain
  });

  console.log('Account:', account.address);
  console.log('Testing addMargin function (same modifier as closePosition)');

  try {
    // Test simulate addMargin - this uses the same onlyPositionOwner modifier
    const addMarginParams = {
      tokenId: 1n,
      amount: 1n, // Just 1 wei to test
      deadline: BigInt(Math.floor(Date.now() / 1000) + 300)
    };

    console.log('Simulating addMargin...');
    const simulationResult = await publicClient.simulateContract({
      address: c.perpsRouter.address,
      abi: c.perpsRouter.abi,
      functionName: 'addMargin',
      args: [addMarginParams],
      account: account.address
    });
    
    console.log('addMargin simulation successful! The modifier works fine.');
    console.log('This means the issue with closePosition is NOT the onlyPositionOwner modifier.');
    
  } catch (error: any) {
    console.log('addMargin simulation failed:', error.message);
    
    if (error.message?.includes('NotPositionOwner')) {
      console.log('Same NotPositionOwner error in addMargin - modifier issue confirmed');
    } else {
      console.log('Different error in addMargin - closePosition has a specific issue');
    }
  }
}

main().catch(console.error);
