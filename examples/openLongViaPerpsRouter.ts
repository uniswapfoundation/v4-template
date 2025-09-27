#!/usr/bin/env bun
import { parseUnits, formatUnits, createWalletClient, http, createPublicClient } from 'viem';
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
    console.log('🎯 Opening Long Position via PerpsRouter (Traditional Approach)');
    console.log('👤 Using account:', account.address);
    console.log('🌐 Chain ID:', CHAIN_ID);

    // Position parameters
    const marginAmount = parseUnits('100', 6); // 100 USDC
    const positionSize = parseUnits('0.1', 18); // 0.1 VETH
    const maxPrice = parseUnits('2100', 6); // Max price 2100 USDC per VETH

    console.log('📊 Position Parameters:');
    console.log('  Margin:', formatUnits(marginAmount, 6), 'USDC');
    console.log('  Size:', formatUnits(positionSize, 18), 'VETH');
    console.log('  Max Price:', formatUnits(maxPrice, 6), 'USDC');

    // Create the PoolKey for the VETH-USDC pool
    const poolKey = {
      currency0: c.mockUSDC.address,   // Currency with lower address
      currency1: c.mockVETH.address,   // Currency with higher address  
      fee: 3000,                       // 0.3% fee tier
      tickSpacing: 60,                 // Standard tick spacing for 0.3%
      hooks: c.perpsHook.address       // Our PerpsHook
    };

    console.log('💱 Pool Configuration:');
    console.log('  Currency0 (USDC):', poolKey.currency0);
    console.log('  Currency1 (VETH):', poolKey.currency1);
    console.log('  Fee:', poolKey.fee, 'bps');
    console.log('  Hook:', poolKey.hooks);

    // Create position parameters using the struct format
    const positionParams = {
      poolKey: poolKey,
      isLong: true,                    // Long position
      marginAmount: marginAmount,      // 100 USDC
      leverage: parseUnits('2', 18),   // 2x leverage
      slippageBps: BigInt(100),        // 1% slippage (100 bps)
      deadline: BigInt(Math.floor(Date.now() / 1000) + 300) // 5 minutes from now
    };

    console.log('� Position Parameters:');
    console.log('  Is Long:', positionParams.isLong);
    console.log('  Margin:', formatUnits(positionParams.marginAmount, 6), 'USDC');
    console.log('  Leverage:', formatUnits(positionParams.leverage, 18) + 'x');
    console.log('  Slippage:', positionParams.slippageBps.toString(), 'bps');

    console.log('🔄 Opening long position via PerpsRouter...');
    
    // Try to open position using PerpsRouter
    const openPositionTx = await walletClient.writeContract({
      address: c.perpsRouter.address,
      abi: c.perpsRouter.abi as any,
      functionName: 'openPosition',
      args: [positionParams]  // Single struct parameter
    });

    console.log('⏳ Transaction submitted:', openPositionTx);
    
    // Wait for confirmation
    const receipt = await publicClient.waitForTransactionReceipt({ hash: openPositionTx });
    console.log('✅ Position opened successfully!');
    console.log('📋 Transaction receipt:', {
      blockNumber: receipt.blockNumber,
      gasUsed: receipt.gasUsed,
      status: receipt.status
    });

    // Try to get the position details (if successful)
    console.log('🔍 Checking for new positions...');
    const userPositions = (await publicClient.readContract({
      address: c.positionManager.address,
      abi: c.positionManager.abi as any,
      functionName: 'getUserPositions',
      args: [account.address]
    })) as bigint[];

    console.log('📊 User positions:', userPositions.map(id => id.toString()));

  } catch (error) {
    console.error('❌ Error opening position via PerpsRouter:', error);
    throw error;
  }
}

if (import.meta.main) {
  main().catch(console.error);
}
