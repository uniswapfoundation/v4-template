#!/usr/bin/env bun
import { parseUnits, createWalletClient, http, createPublicClient } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { unichainSepolia } from 'viem/chains';
import { getContracts } from './contracts';

// Constants
const CHAIN_ID = 1301; // Unichain Sepolia
const RPC_URL = 'https://sepolia.unichain.org';

// Get contracts
const c = getContracts();

// Environment setup - handle private key format
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

const account = privateKeyToAccount(PK as `0x${string}`);

// Clients
const publicClient = createPublicClient({
  chain: unichainSepolia,
  transport: http(RPC_URL)
});

const walletClient = createWalletClient({
  account,
  chain: unichainSepolia,
  transport: http(RPC_URL)
});

async function main() {
  try {
    console.log('🏪 Adding VETH-USDC Market to Position Management System');
    console.log('👤 Using account:', account.address);
    
    // Calculate the market ID as done in the tests
    const marketId = `0x${Buffer.from('VETH/USDC').toString('hex').padEnd(64, '0')}`;
    console.log('📊 Market ID:', marketId);
    
    console.log('💱 Market Configuration:');
    console.log('  Base Asset (VETH):', c.mockVETH.address);
    console.log('  Quote Asset (USDC):', c.mockUSDC.address);
    console.log('  Pool Address: Mock Pool Address (0x1)');
    
    // Add market to the PositionManager (which handles both MarketManager and PositionFactory)
    console.log('🔄 Adding market to PositionManager...');
    
    const addMarketTx = await walletClient.writeContract({
      address: c.positionManager.address,
      abi: c.positionManager.abi as any,
      functionName: 'addMarket',
      args: [
        marketId,                    // bytes32 marketId
        c.mockVETH.address,         // base asset (VETH) 
        c.mockUSDC.address,         // quote asset (USDC)
        '0x0000000000000000000000000000000000000001' // Mock pool address
      ]
    });
    
    console.log('⏳ Transaction submitted:', addMarketTx);
    
    // Wait for confirmation
    const receipt = await publicClient.waitForTransactionReceipt({ hash: addMarketTx });
    console.log('✅ Market added successfully!');
    console.log('📋 Transaction receipt:', {
      blockNumber: receipt.blockNumber,
      gasUsed: receipt.gasUsed,
      status: receipt.status
    });
    
    console.log('✨ Market VETH/USDC is now ready for trading!');
    
  } catch (error) {
    console.error('❌ Error adding market:', error);
    throw error;
  }
}

if (import.meta.main) {
  main().catch(console.error);
}
