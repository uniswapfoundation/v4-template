import 'dotenv/config';
import { http, createWalletClient, createPublicClient, defineChain, encodeAbiParameters, keccak256 } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
const PK = (process.env.PRIVATE_KEY || '').startsWith('0x') ? process.env.PRIVATE_KEY! : `0x${process.env.PRIVATE_KEY || ''}`;
if (!PK || PK.length < 10) throw new Error('PRIVATE_KEY missing - set in .env file');

const account = privateKeyToAccount(PK as `0x${string}`);

const unichain = defineChain({
  id: CHAIN_ID,
  name: 'Unichain Sepolia',
  network: 'unichain-sepolia',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] }, public: { http: [RPC_URL] } },
  blockExplorers: { default: { name: 'Uniscan', url: 'https://sepolia.uniscan.xyz' } },
});

const walletClient = createWalletClient({
  account,
  chain: unichain,
  transport: http(RPC_URL),
});

const publicClient = createPublicClient({
  chain: unichain,
  transport: http(RPC_URL),
});

async function setupLiquidationSystem() {
  try {
    console.log('🔧 Setting up UniPerp Liquidation System');
    console.log('👤 Using account:', account.address);

    const c = getContracts();
    
    // Generate pool ID
    const poolId = keccak256(
      encodeAbiParameters(
        [
          { name: 'currency0', type: 'address' },
          { name: 'currency1', type: 'address' },
          { name: 'fee', type: 'uint24' },
          { name: 'tickSpacing', type: 'int24' },
          { name: 'hooks', type: 'address' }
        ],
        [
          c.mockVETH.address as `0x${string}`,
          c.mockUSDC.address as `0x${string}`,
          3000,
          60,
          c.perpsHook.address as `0x${string}`
        ]
      )
    );

    console.log('🆔 Pool ID:', poolId);

    // Check current liquidation configuration
    console.log('\n📊 Checking current liquidation configuration...');
    
    try {
      const config = await publicClient.readContract({
        address: c.liquidationEngine.address,
        abi: c.liquidationEngine.abi as any,
        functionName: 'getLiquidationConfig',
        args: [poolId]
      }) as any;

      console.log('Current Configuration:');
      console.log('  Maintenance Margin Ratio:', Number(config.maintenanceMarginRatio) / 100, '%');
      console.log('  Liquidation Fee Rate:', Number(config.liquidationFeeRate) / 100, '%');
      console.log('  Insurance Fee Rate:', Number(config.insuranceFeeRate) / 100, '%');
      console.log('  Is Active:', config.isActive);

      if (config.isActive && config.maintenanceMarginRatio > 0n) {
        console.log('✅ Liquidation system is already configured');
        return;
      }
    } catch (error) {
      console.log('❌ Error reading config, will setup new configuration');
    }

    // Setup liquidation configuration
    console.log('\n⚙️ Configuring liquidation parameters...');
    
    const configTx = await walletClient.writeContract({
      address: c.liquidationEngine.address,
      abi: c.liquidationEngine.abi as any,
      functionName: 'configureLiquidation',
      args: [
        poolId,
        500,  // 5% maintenance margin ratio (500 basis points)
        250,  // 2.5% liquidation fee rate (250 basis points)
        250,  // 2.5% insurance fee rate (250 basis points)  
        true  // activate liquidations
      ]
    });

    console.log('⏳ Waiting for liquidation configuration...');
    const configReceipt = await publicClient.waitForTransactionReceipt({ hash: configTx });

    if (configReceipt.status === 'success') {
      console.log('✅ Liquidation configuration set successfully!');
      console.log('📋 Transaction Hash:', configTx);
    } else {
      console.error('❌ Liquidation configuration failed');
      return;
    }

    // Verify the configuration
    console.log('\n📋 Verifying configuration...');
    const newConfig = await publicClient.readContract({
      address: c.liquidationEngine.address,
      abi: c.liquidationEngine.abi as any,
      functionName: 'getLiquidationConfig',
      args: [poolId]
    }) as any;

    console.log('✅ Verified Configuration:');
    console.log('  Maintenance Margin Ratio:', Number(newConfig.maintenanceMarginRatio) / 100, '%');
    console.log('  Liquidation Fee Rate:', Number(newConfig.liquidationFeeRate) / 100, '%');
    console.log('  Insurance Fee Rate:', Number(newConfig.insuranceFeeRate) / 100, '%');
    console.log('  Is Active:', newConfig.isActive);

    // Test liquidation check on an existing position
    console.log('\n🧪 Testing liquidation system on existing positions...');
    
    const testTokenIds = [1, 3, 5, 6, 7];
    
    for (const tokenId of testTokenIds) {
      try {
        const position = await publicClient.readContract({
          address: c.positionManager.address,
          abi: c.positionManager.abi as any,
          functionName: 'getPosition',
          args: [tokenId]
        }) as any;

        if (position.owner === '0x0000000000000000000000000000000000000000') {
          console.log(`  Position #${tokenId}: Not found`);
          continue;
        }

        const [isLiquidatable, currentPrice, healthFactor] = await publicClient.readContract({
          address: c.liquidationEngine.address,
          abi: c.liquidationEngine.abi as any,
          functionName: 'isPositionLiquidatable',
          args: [tokenId]
        }) as [boolean, bigint, bigint];

        console.log(`  Position #${tokenId}:`);
        console.log(`    Health Factor: ${Number(healthFactor) / 1e18}`);
        console.log(`    Is Liquidatable: ${isLiquidatable}`);
        console.log(`    Current Price: $${Number(currentPrice) / 1e18}`);

      } catch (error) {
        console.log(`  Position #${tokenId}: Error checking - ${error}`);
      }
    }

    console.log('\n🎉 Liquidation system setup complete!');
    console.log('\n💡 Next Steps:');
    console.log('  🔍 Scan positions: bun run liquidationScanner.ts');
    console.log('  🤖 Start bot: bun run liquidationBot.ts');
    console.log('  🎯 Manual liquidation: bun run liquidationBot.ts manual <tokenId>');

  } catch (error) {
    console.error('❌ Error setting up liquidation system:', error);
  }
}

setupLiquidationSystem().catch(console.error);
