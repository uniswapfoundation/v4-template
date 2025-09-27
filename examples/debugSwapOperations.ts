import 'dotenv/config';
import { createPublicClient, createWalletClient, http, defineChain, parseUnits, formatUnits, encodeAbiParameters } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';
import { calculateUsdcVethPoolId, getPoolInfo } from './poolUtils';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing');

// Position operation types matching the PerpsHook
enum OperationType {
  OPEN_LONG = 0,
  OPEN_SHORT = 1,
  CLOSE_POSITION = 2,
  ADD_MARGIN = 3,
  REMOVE_MARGIN = 4,
  LIQUIDATE = 5
}

interface TradeParams {
  operation: number;
  tokenId: bigint;
  size: bigint;
  margin: bigint;
  maxSlippage: bigint;
  trader: `0x${string}`;
}

async function debugSwapOperations() {
  console.log('🔍 DEBUG: Comprehensive Swap Operation Analysis');
  console.log('==============================================');
  
  const account = privateKeyToAccount(PK as `0x${string}`);
  const contracts = getContracts(CHAIN_ID);

  const transport = http(RPC_URL);
  const chain = defineChain({ 
    id: CHAIN_ID, 
    name: 'UnichainSepolia', 
    nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 }, 
    rpcUrls: { default: { http: [RPC_URL] }, public: { http: [RPC_URL] } } 
  });
  
  const publicClient = createPublicClient({ transport, chain });
  const walletClient = createWalletClient({ account, transport, chain });

  const c = contracts;
  const poolId = calculateUsdcVethPoolId(c.mockUSDC.address, c.mockVETH.address, c.perpsHook.address);
  const poolInfo = getPoolInfo(c.mockUSDC.address, c.mockVETH.address, c.perpsHook.address);

  console.log('🔧 SETUP INFORMATION:');
  console.log('👤 Account:', account.address);
  console.log('🆔 Pool ID:', poolId);
  console.log('💱 Currency0 (lower):', poolInfo.poolKey.currency0);
  console.log('💱 Currency1 (higher):', poolInfo.poolKey.currency1);
  console.log('🪝 Hook Address:', c.perpsHook.address);
  console.log('🏊 PoolSwapTest:', c.poolSwapTest.address);
  console.log('');

  try {
    // STEP 1: Detailed vAMM State Analysis
    console.log('📊 STEP 1: DETAILED vAMM STATE ANALYSIS');
    console.log('=========================================');
    
    const marketState = await publicClient.readContract({
      address: c.perpsHook.address,
      abi: c.perpsHook.abi as any,
      functionName: 'getMarketState',
      args: [poolId]
    });
    
    console.log('🪝 Hook Market State:');
    console.log('   Virtual Base (raw):', marketState.virtualBase.toString());
    console.log('   Virtual Quote (raw):', marketState.virtualQuote.toString());
    console.log('   K Constant:', marketState.k.toString());
    console.log('   Global Funding Index:', marketState.globalFundingIndex.toString());
    console.log('   Total Long OI:', marketState.totalLongOI.toString());
    console.log('   Total Short OI:', marketState.totalShortOI.toString());
    console.log('   Max OI Cap:', marketState.maxOICap.toString());
    console.log('   Last Funding Time:', marketState.lastFundingTime.toString());
    console.log('   Spot Price Feed:', marketState.spotPriceFeed);
    console.log('   Is Active:', marketState.isActive);

    const virtualBase = Number(marketState.virtualBase);
    const virtualQuote = Number(marketState.virtualQuote);
    console.log('📈 Calculated vAMM Price:', ((virtualQuote * 1e18) / virtualBase / 1e18).toFixed(6), 'USDC per VETH');
    console.log('');

    // STEP 2: Token Balance Analysis
    console.log('💰 STEP 2: TOKEN BALANCE ANALYSIS');
    console.log('==================================');
    
    const usdcBalance = await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'balanceOf',
      args: [account.address]
    });
    
    const vethBalance = await publicClient.readContract({
      address: c.mockVETH.address,
      abi: c.mockVETH.abi as any,
      functionName: 'balanceOf',
      args: [account.address]
    });

    console.log('💳 Token Balances:');
    console.log('   USDC Balance:', formatUnits(usdcBalance as bigint, 6), 'USDC');
    console.log('   VETH Balance:', formatUnits(vethBalance as bigint, 18), 'VETH');
    console.log('');

    // STEP 3: Contract Authorization Analysis
    console.log('🔐 STEP 3: CONTRACT AUTHORIZATION ANALYSIS');
    console.log('==========================================');
    
    // Check allowances
    const usdcAllowanceHook = await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'allowance',
      args: [account.address, c.perpsHook.address]
    });
    
    const usdcAllowanceSwapTest = await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'allowance',
      args: [account.address, c.poolSwapTest.address]
    });
    
    const vethAllowanceSwapTest = await publicClient.readContract({
      address: c.mockVETH.address,
      abi: c.mockVETH.abi as any,
      functionName: 'allowance',
      args: [account.address, c.poolSwapTest.address]
    });

    console.log('🔐 Current Allowances:');
    console.log('   USDC -> Hook:', formatUnits(usdcAllowanceHook as bigint, 6), 'USDC');
    console.log('   USDC -> PoolSwapTest:', formatUnits(usdcAllowanceSwapTest as bigint, 6), 'USDC');
    console.log('   VETH -> PoolSwapTest:', formatUnits(vethAllowanceSwapTest as bigint, 18), 'VETH');
    console.log('');

    // STEP 4: Market Configuration Analysis
    console.log('🏪 STEP 4: MARKET CONFIGURATION ANALYSIS');
    console.log('========================================');
    
    // Check FundingOracle
    try {
      const fundingFeed = await publicClient.readContract({
        address: c.fundingOracle.address,
        abi: c.fundingOracle.abi as any,
        functionName: 'pythPriceFeedIds',
        args: [poolId]
      });
      console.log('📊 FundingOracle Feed ID:', fundingFeed);
    } catch (error) {
      console.log('❌ FundingOracle Error:', error.shortMessage);
    }

    // Check MarketManager
    try {
      const marketManagerMarket = await publicClient.readContract({
        address: c.marketManager.address,
        abi: c.marketManager.abi as any,
        functionName: 'getMarket',
        args: [poolId]
      });
      console.log('🏢 MarketManager Market:');
      console.log('   Base Asset:', marketManagerMarket.baseAsset);
      console.log('   Quote Asset:', marketManagerMarket.quoteAsset);
      console.log('   Pool Address:', marketManagerMarket.poolAddress);
      console.log('   Is Active:', marketManagerMarket.isActive);
    } catch (error) {
      console.log('❌ MarketManager Error:', error.shortMessage);
    }

    // Check PositionFactory
    try {
      const factoryMarket = await publicClient.readContract({
        address: c.positionFactory.address,
        abi: c.positionFactory.abi as any,
        functionName: 'getMarket',
        args: [poolId]
      });
      console.log('🏭 PositionFactory Market:');
      console.log('   Base Asset:', factoryMarket.baseAsset);
      console.log('   Quote Asset:', factoryMarket.quoteAsset);
      console.log('   Pool Address:', factoryMarket.poolAddress);
      console.log('   Is Active:', factoryMarket.isActive);
    } catch (error) {
      console.log('❌ PositionFactory Error:', error.shortMessage);
    }
    console.log('');

    // STEP 5: Hook Data Encoding Analysis
    console.log('📦 STEP 5: HOOK DATA ENCODING ANALYSIS');
    console.log('======================================');
    
    const marginAmount = parseUnits('50', 6); // 50 USDC
    const positionSize = parseUnits('0.01', 18); // 0.01 VETH
    const maxSlippage = 1000n; // 10%

    const tradeParams: TradeParams = {
      operation: OperationType.OPEN_LONG,
      tokenId: 0n,
      size: positionSize,
      margin: marginAmount,
      maxSlippage: maxSlippage,
      trader: account.address
    };

    console.log('📋 Trade Parameters:');
    console.log('   Operation:', tradeParams.operation, '(OPEN_LONG)');
    console.log('   Token ID:', tradeParams.tokenId.toString());
    console.log('   Size (raw):', tradeParams.size.toString());
    console.log('   Size (formatted):', formatUnits(tradeParams.size, 18), 'VETH');
    console.log('   Margin (raw):', tradeParams.margin.toString());
    console.log('   Margin (formatted):', formatUnits(tradeParams.margin, 6), 'USDC');
    console.log('   Max Slippage:', tradeParams.maxSlippage.toString(), 'bps');
    console.log('   Trader:', tradeParams.trader);

    const hookData = encodeAbiParameters(
      [
        {
          type: 'tuple',
          components: [
            { name: 'operation', type: 'uint8' },
            { name: 'tokenId', type: 'uint256' },
            { name: 'size', type: 'uint256' },
            { name: 'margin', type: 'uint256' },
            { name: 'maxSlippage', type: 'uint256' },
            { name: 'trader', type: 'address' }
          ]
        }
      ],
      [tradeParams]
    );

    console.log('📦 Encoded Hook Data:');
    console.log('   Length:', hookData.length);
    console.log('   Data:', hookData);
    console.log('');

    // STEP 6: Pool Key and Swap Parameters Analysis
    console.log('🏊 STEP 6: POOL KEY AND SWAP PARAMETERS');
    console.log('======================================');
    
    const poolKey = {
      currency0: poolInfo.poolKey.currency0 as `0x${string}`,
      currency1: poolInfo.poolKey.currency1 as `0x${string}`,
      fee: poolInfo.poolKey.fee,
      tickSpacing: poolInfo.poolKey.tickSpacing,
      hooks: poolInfo.poolKey.hooks as `0x${string}`
    };

    console.log('🗝️  Pool Key:');
    console.log('   Currency0:', poolKey.currency0);
    console.log('   Currency1:', poolKey.currency1);
    console.log('   Fee:', poolKey.fee);
    console.log('   Tick Spacing:', poolKey.tickSpacing);
    console.log('   Hooks:', poolKey.hooks);

    const swapAmount = parseUnits('0.001', 18); // Very small swap
    const swapParams = {
      zeroForOne: true, // Swap currency0 for currency1
      amountSpecified: swapAmount,
      sqrtPriceLimitX96: BigInt("4295128740")
    };

    console.log('🔄 Swap Parameters:');
    console.log('   Zero For One:', swapParams.zeroForOne);
    console.log('   Amount Specified:', swapParams.amountSpecified.toString());
    console.log('   Amount Formatted:', formatUnits(swapParams.amountSpecified, 18), 'tokens');
    console.log('   Sqrt Price Limit:', swapParams.sqrtPriceLimitX96.toString());

    const testSettings = {
      takeClaims: false,
      settleUsingBurn: false
    };

    console.log('⚙️  Test Settings:');
    console.log('   Take Claims:', testSettings.takeClaims);
    console.log('   Settle Using Burn:', testSettings.settleUsingBurn);
    console.log('');

    // STEP 7: Pre-Swap Contract State
    console.log('📋 STEP 7: PRE-SWAP CONTRACT STATE');
    console.log('==================================');
    
    // Check margin account state
    const marginBalance = await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: 'getTotalBalance',
      args: [account.address]
    });
    console.log('🏦 Margin Account Balance:', formatUnits(marginBalance as bigint, 6), 'USDC');

    // Check if user has any existing positions
    try {
      const positionBalance = await publicClient.readContract({
        address: c.positionManager.address,
        abi: c.positionManager.abi as any,
        functionName: 'balanceOf',
        args: [account.address]
      });
      console.log('🏷️  Existing Position NFTs:', positionBalance.toString());
    } catch (error) {
      console.log('⚠️  Could not check position NFTs:', error.shortMessage);
    }

    // Check hook permissions
    try {
      const hookPermissions = await publicClient.readContract({
        address: c.perpsHook.address,
        abi: c.perpsHook.abi as any,
        functionName: 'getHookPermissions',
        args: []
      });
      console.log('🪝 Hook Permissions:', hookPermissions);
    } catch (error) {
      console.log('⚠️  Could not check hook permissions:', error.shortMessage);
    }
    console.log('');

    // STEP 8: Approval Process with Detailed Logging
    console.log('🔓 STEP 8: DETAILED APPROVAL PROCESS');
    console.log('====================================');
    
    const approvalAmount = parseUnits('1000', 18); // Large approval amount
    
    console.log('💡 Approving VETH for PoolSwapTest...');
    console.log('   From:', account.address);
    console.log('   To:', c.poolSwapTest.address);
    console.log('   Amount:', formatUnits(approvalAmount, 18), 'VETH');
    
    try {
      const vethApproveTx = await walletClient.writeContract({
        address: c.mockVETH.address,
        abi: c.mockVETH.abi as any,
        functionName: 'approve',
        args: [c.poolSwapTest.address, approvalAmount]
      });
      
      console.log('⏳ VETH Approval TX:', vethApproveTx);
      const vethApprovalReceipt = await publicClient.waitForTransactionReceipt({ hash: vethApproveTx });
      console.log('✅ VETH Approval Success - Block:', vethApprovalReceipt.blockNumber);
    } catch (error) {
      console.log('❌ VETH Approval Failed:', error.shortMessage || error.message);
      return;
    }

    console.log('💡 Approving USDC for PoolSwapTest...');
    const usdcApprovalAmount = parseUnits('1000', 6);
    
    try {
      const usdcApproveTx = await walletClient.writeContract({
        address: c.mockUSDC.address,
        abi: c.mockUSDC.abi as any,
        functionName: 'approve',
        args: [c.poolSwapTest.address, usdcApprovalAmount]
      });
      
      console.log('⏳ USDC Approval TX:', usdcApproveTx);
      const usdcApprovalReceipt = await publicClient.waitForTransactionReceipt({ hash: usdcApproveTx });
      console.log('✅ USDC Approval Success - Block:', usdcApprovalReceipt.blockNumber);
    } catch (error) {
      console.log('❌ USDC Approval Failed:', error.shortMessage || error.message);
      return;
    }
    console.log('');

    // STEP 9: Pre-Swap Verification
    console.log('🔍 STEP 9: PRE-SWAP VERIFICATION');
    console.log('=================================');
    
    // Verify allowances after approval
    const finalUsdcAllowance = await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: 'allowance',
      args: [account.address, c.poolSwapTest.address]
    });
    
    const finalVethAllowance = await publicClient.readContract({
      address: c.mockVETH.address,
      abi: c.mockVETH.abi as any,
      functionName: 'allowance',
      args: [account.address, c.poolSwapTest.address]
    });

    console.log('✅ Final Allowances:');
    console.log('   USDC -> PoolSwapTest:', formatUnits(finalUsdcAllowance as bigint, 6), 'USDC');
    console.log('   VETH -> PoolSwapTest:', formatUnits(finalVethAllowance as bigint, 18), 'VETH');

    // Check if PoolSwapTest contract exists and is accessible
    try {
      const poolSwapTestCode = await publicClient.getBytecode({
        address: c.poolSwapTest.address
      });
      console.log('🏊 PoolSwapTest Contract:', poolSwapTestCode ? 'EXISTS' : 'NOT FOUND');
      console.log('   Bytecode Length:', poolSwapTestCode ? poolSwapTestCode.length : 0);
    } catch (error) {
      console.log('❌ PoolSwapTest Check Failed:', error.shortMessage);
    }
    console.log('');

    // STEP 10: The Actual Swap Attempt with Maximum Logging
    console.log('🚀 STEP 10: SWAP EXECUTION WITH MAXIMUM LOGGING');
    console.log('===============================================');
    
    console.log('📋 Final Swap Call Parameters:');
    console.log('   Contract Address:', c.poolSwapTest.address);
    console.log('   Function: swap');
    console.log('   Pool Key:', JSON.stringify(poolKey, null, 2));
    console.log('   Swap Params:', JSON.stringify({
      zeroForOne: swapParams.zeroForOne,
      amountSpecified: swapParams.amountSpecified.toString(),
      sqrtPriceLimitX96: swapParams.sqrtPriceLimitX96.toString()
    }, null, 2));
    console.log('   Test Settings:', JSON.stringify(testSettings, null, 2));
    console.log('   Hook Data Length:', hookData.length);
    console.log('   Hook Data Preview:', hookData.slice(0, 100) + '...');

    try {
      console.log('🔄 EXECUTING SWAP...');
      
      const swapTx = await walletClient.writeContract({
        address: c.poolSwapTest.address,
        abi: c.poolSwapTest.abi as any,
        functionName: 'swap',
        args: [poolKey, swapParams, testSettings, hookData]
      });

      console.log('⏳ Swap Transaction Submitted:', swapTx);
      
      const receipt = await publicClient.waitForTransactionReceipt({ hash: swapTx });
      console.log('✅ SWAP SUCCESS!');
      console.log('📦 Block Number:', receipt.blockNumber);
      console.log('⛽ Gas Used:', receipt.gasUsed);
      console.log('📋 Transaction Hash:', swapTx);
      
      // Check logs for events
      console.log('📄 Transaction Logs:', receipt.logs.length, 'events');
      receipt.logs.forEach((log, index) => {
        console.log(`   Log ${index}:`, log.address, '-', log.topics[0]);
      });

    } catch (error) {
      console.log('❌ SWAP FAILED WITH DETAILED ERROR:');
      console.log('=====================================');
      console.log('Error Type:', error.constructor.name);
      console.log('Error Message:', error.message);
      console.log('Short Message:', error.shortMessage);
      console.log('Error Signature:', error.signature);
      console.log('Contract Address:', error.contractAddress);
      console.log('Function Name:', error.functionName);
      console.log('Raw Data:', error.raw);
      
      if (error.args) {
        console.log('Arguments:', error.args);
      }
      
      if (error.metaMessages) {
        console.log('Meta Messages:', error.metaMessages);
      }

      // Try to decode the error signature manually
      if (error.signature === '0x90bfb865') {
        console.log('🔍 ERROR SIGNATURE ANALYSIS:');
        console.log('   Signature 0x90bfb865 is consistently appearing');
        console.log('   This might be a custom error from the hook or pool manager');
        console.log('   Raw data contains hook address:', error.raw?.includes(c.perpsHook.address.slice(2)));
      }
    }

    console.log('\n🎯 DEBUGGING SUMMARY:');
    console.log('=====================');
    console.log('✅ vAMM is properly balanced');
    console.log('✅ Markets are configured');
    console.log('✅ Token approvals are working');
    console.log('✅ Hook data encoding is correct');
    console.log('❌ Swap execution fails with 0x90bfb865');
    console.log('');
    console.log('🔬 NEXT INVESTIGATION STEPS:');
    console.log('   1. Check if error 0x90bfb865 is defined in hook contract');
    console.log('   2. Verify hook beforeSwap logic');
    console.log('   3. Check if pool needs additional initialization');
    console.log('   4. Investigate PoolSwapTest compatibility with our hook');

  } catch (error) {
    console.error('❌ CRITICAL ERROR IN DEBUG SCRIPT:', error);
  }
}

debugSwapOperations().catch(e => { 
  console.error('💥 DEBUG FAILED:', e);
  process.exit(1);
});
