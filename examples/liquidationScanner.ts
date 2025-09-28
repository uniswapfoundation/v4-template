import 'dotenv/config';
import { http, createPublicClient, defineChain, encodeAbiParameters, keccak256 } from 'viem';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

// Pyth ETH/USD price feed ID
const PYTH_ETH_USD_FEED_ID = '0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace';

// Function to fetch real-time ETH price from Pyth
async function fetchPythPrice(): Promise<number> {
  try {
    const response = await fetch(`https://hermes.pyth.network/api/latest_price_feeds?ids[]=${PYTH_ETH_USD_FEED_ID}`);
    const data = await response.json();
    
    if (data && data.length > 0) {
      const priceData = data[0].price;
      const price = parseInt(priceData.price);
      const expo = priceData.expo;
      const actualPrice = price * Math.pow(10, expo);
      return actualPrice;
    } else {
      throw new Error('No price data received from Pyth');
    }
  } catch (error) {
    console.error('❌ Failed to fetch Pyth price:', error);
    return 4000; // Fallback price
  }
}

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);

const unichain = defineChain({
  id: CHAIN_ID,
  name: 'Unichain Sepolia',
  network: 'unichain-sepolia',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] }, public: { http: [RPC_URL] } },
  blockExplorers: { default: { name: 'Uniscan', url: 'https://sepolia.uniscan.xyz' } },
});

const publicClient = createPublicClient({
  chain: unichain,
  transport: http(RPC_URL),
});

interface PositionRisk {
  tokenId: number;
  owner: string;
  healthFactor: number;
  isLiquidatable: boolean;
  currentPrice: number;
  entryPrice: number;
  margin: number;
  positionSize: number;
  isLong: boolean;
  unrealizedPnL: number;
  liquidationPrice: number;
  riskLevel: 'SAFE' | 'WARNING' | 'DANGER' | 'LIQUIDATABLE';
}

async function scanLiquidationRisks() {
  try {
    console.log('🔍 UniPerp Liquidation Risk Scanner');
    console.log('=====================================\n');

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

    // Fetch current ETH price
    const pythPrice = await fetchPythPrice();
    console.log('📡 Current ETH Price:', pythPrice.toFixed(2), 'USD (Pyth Network)\n');

    // Get current mark price from hook
    const markPrice = await publicClient.readContract({
      address: c.perpsHook.address,
      abi: c.perpsHook.abi as any,
      functionName: 'getMarkPrice',
      args: [poolId]
    }) as bigint;

    console.log('📊 Current Mark Price:', Number(markPrice) / 1e18, 'USD (vAMM)\n');

    // Check liquidation configuration
    const liquidationConfig = await publicClient.readContract({
      address: c.liquidationEngine.address,
      abi: c.liquidationEngine.abi as any,
      functionName: 'getLiquidationConfig',
      args: [poolId]
    }) as any;

    if (!liquidationConfig.isActive) {
      console.log('⚠️ WARNING: Liquidations are not active for this market!');
      console.log('   Run: bun run liquidationBot.ts to setup liquidation config\n');
    } else {
      console.log('⚙️ Liquidation Configuration:');
      console.log('  Maintenance Margin Ratio:', Number(liquidationConfig.maintenanceMarginRatio) / 100, '%');
      console.log('  Liquidation Fee Rate:', Number(liquidationConfig.liquidationFeeRate) / 100, '%');
      console.log('  Insurance Fee Rate:', Number(liquidationConfig.insuranceFeeRate) / 100, '%');
      console.log('  Status: ACTIVE ✅\n');
    }

    // Scan for active positions
    const activePositions = await getAllActivePositions(c);
    
    if (activePositions.length === 0) {
      console.log('📊 No active positions found');
      return;
    }

    console.log(`📊 Found ${activePositions.length} active positions to analyze\n`);

    // Analyze each position
    const positionRisks: PositionRisk[] = [];
    
    for (const tokenId of activePositions) {
      try {
        const risk = await analyzePositionRisk(c, tokenId, pythPrice);
        if (risk) {
          positionRisks.push(risk);
        }
      } catch (error) {
        console.error(`❌ Error analyzing position ${tokenId}:`, error);
      }
    }

    // Sort by risk level and health factor
    positionRisks.sort((a, b) => {
      const riskOrder = { 'LIQUIDATABLE': 0, 'DANGER': 1, 'WARNING': 2, 'SAFE': 3 };
      if (riskOrder[a.riskLevel] !== riskOrder[b.riskLevel]) {
        return riskOrder[a.riskLevel] - riskOrder[b.riskLevel];
      }
      return a.healthFactor - b.healthFactor;
    });

    // Display results
    displayRiskAnalysis(positionRisks);

  } catch (error) {
    console.error('❌ Error in liquidation scanner:', error);
  }
}

async function getAllActivePositions(contracts: any): Promise<number[]> {
  const activePositions: number[] = [];
  const maxTokenId = 100; // Adjust based on your system

  for (let tokenId = 1; tokenId <= maxTokenId; tokenId++) {
    try {
      const position = await publicClient.readContract({
        address: contracts.positionManager.address,
        abi: contracts.positionManager.abi as any,
        functionName: 'getPosition',
        args: [tokenId]
      }) as any;

      if (position.owner !== '0x0000000000000000000000000000000000000000' && position.sizeBase !== 0n) {
        activePositions.push(tokenId);
      }
    } catch (error) {
      continue;
    }
  }

  return activePositions;
}

async function analyzePositionRisk(contracts: any, tokenId: number, currentPrice: number): Promise<PositionRisk | null> {
  try {
    // Get position details
    const position = await publicClient.readContract({
      address: contracts.positionManager.address,
      abi: contracts.positionManager.abi as any,
      functionName: 'getPosition',
      args: [tokenId]
    }) as any;

    // Get liquidation status
    const [isLiquidatable, price, healthFactor] = await publicClient.readContract({
      address: contracts.liquidationEngine.address,
      abi: contracts.liquidationEngine.abi as any,
      functionName: 'isPositionLiquidatable',
      args: [tokenId]
    }) as [boolean, bigint, bigint];

    const positionSize = Number(position.sizeBase) / 1e18;
    const isLong = position.sizeBase > 0n;
    const margin = Number(position.margin) / 1e6;
    const entryPrice = Number(position.entryPrice) / 1e18;
    const healthFactorDecimal = Number(healthFactor) / 1e18;

    // Calculate unrealized PnL
    const priceDiff = currentPrice - entryPrice;
    const unrealizedPnL = isLong ? (positionSize * priceDiff) : (-positionSize * priceDiff);

    // Calculate liquidation price (approximate)
    const maintenanceMarginRatio = 0.05; // 5% default
    const liquidationPrice = isLong 
      ? entryPrice * (1 - (margin / Math.abs(positionSize)) + maintenanceMarginRatio)
      : entryPrice * (1 + (margin / Math.abs(positionSize)) - maintenanceMarginRatio);

    // Determine risk level
    let riskLevel: 'SAFE' | 'WARNING' | 'DANGER' | 'LIQUIDATABLE';
    if (isLiquidatable) {
      riskLevel = 'LIQUIDATABLE';
    } else if (healthFactorDecimal < 1.1) {
      riskLevel = 'DANGER';
    } else if (healthFactorDecimal < 1.5) {
      riskLevel = 'WARNING';
    } else {
      riskLevel = 'SAFE';
    }

    return {
      tokenId,
      owner: position.owner,
      healthFactor: healthFactorDecimal,
      isLiquidatable,
      currentPrice: Number(price) / 1e18,
      entryPrice,
      margin,
      positionSize: Math.abs(positionSize),
      isLong,
      unrealizedPnL,
      liquidationPrice,
      riskLevel
    };

  } catch (error) {
    console.error(`Error analyzing position ${tokenId}:`, error);
    return null;
  }
}

function displayRiskAnalysis(positions: PositionRisk[]) {
  const liquidatable = positions.filter(p => p.riskLevel === 'LIQUIDATABLE');
  const danger = positions.filter(p => p.riskLevel === 'DANGER');
  const warning = positions.filter(p => p.riskLevel === 'WARNING');
  const safe = positions.filter(p => p.riskLevel === 'SAFE');

  console.log('📊 LIQUIDATION RISK ANALYSIS');
  console.log('============================');
  console.log(`🔴 LIQUIDATABLE: ${liquidatable.length}`);
  console.log(`🟠 DANGER: ${danger.length}`);
  console.log(`🟡 WARNING: ${warning.length}`);
  console.log(`🟢 SAFE: ${safe.length}\n`);

  if (liquidatable.length > 0) {
    console.log('🚨 LIQUIDATABLE POSITIONS (IMMEDIATE ACTION REQUIRED)');
    console.log('====================================================');
    liquidatable.forEach(pos => {
      console.log(`💀 Position #${pos.tokenId} (${pos.isLong ? 'LONG' : 'SHORT'})`);
      console.log(`   Owner: ${pos.owner}`);
      console.log(`   Health Factor: ${pos.healthFactor.toFixed(3)} (< 1.0 = liquidatable)`);
      console.log(`   Position Size: ${pos.positionSize.toFixed(4)} VETH`);
      console.log(`   Margin: ${pos.margin.toFixed(2)} USDC`);
      console.log(`   Entry Price: $${pos.entryPrice.toFixed(2)}`);
      console.log(`   Current Price: $${pos.currentPrice.toFixed(2)}`);
      console.log(`   Unrealized PnL: ${pos.unrealizedPnL.toFixed(2)} USDC`);
      console.log(`   💡 Action: bun run liquidationBot.ts manual ${pos.tokenId}`);
      console.log('');
    });
  }

  if (danger.length > 0) {
    console.log('⚠️  HIGH RISK POSITIONS (MONITOR CLOSELY)');
    console.log('==========================================');
    danger.forEach(pos => {
      console.log(`🔴 Position #${pos.tokenId} (${pos.isLong ? 'LONG' : 'SHORT'})`);
      console.log(`   Health Factor: ${pos.healthFactor.toFixed(3)} (very low)`);
      console.log(`   Unrealized PnL: ${pos.unrealizedPnL.toFixed(2)} USDC`);
      console.log(`   Liquidation Price: $${pos.liquidationPrice.toFixed(2)}`);
      console.log('');
    });
  }

  if (warning.length > 0) {
    console.log('🟡 MEDIUM RISK POSITIONS');
    console.log('========================');
    warning.forEach(pos => {
      console.log(`⚠️  Position #${pos.tokenId} (${pos.isLong ? 'LONG' : 'SHORT'})`);
      console.log(`   Health Factor: ${pos.healthFactor.toFixed(3)}`);
      console.log(`   Unrealized PnL: ${pos.unrealizedPnL.toFixed(2)} USDC`);
      console.log('');
    });
  }

  console.log('💡 LIQUIDATION COMMANDS:');
  console.log('========================');
  console.log('🤖 Start automated bot: bun run liquidationBot.ts');
  console.log('🎯 Manual liquidation: bun run liquidationBot.ts manual <tokenId>');
  console.log('🔍 Scan again: bun run liquidationScanner.ts');
  console.log('📊 View portfolio: bun run portfolioOverviewFixed.ts');
}

// Get command line arguments
const args = process.argv.slice(2);
if (args.length > 0 && args[0] === '--help') {
  console.log('UniPerp Liquidation Scanner');
  console.log('===========================');
  console.log('Usage: bun run liquidationScanner.ts');
  console.log('');
  console.log('This script scans all active positions and analyzes their liquidation risk.');
  console.log('It provides a comprehensive risk assessment without executing any liquidations.');
  console.log('');
  console.log('Risk Levels:');
  console.log('🔴 LIQUIDATABLE - Position can be liquidated immediately');
  console.log('🟠 DANGER - Health factor < 1.1 (very close to liquidation)');
  console.log('🟡 WARNING - Health factor < 1.5 (moderate risk)');
  console.log('🟢 SAFE - Health factor >= 1.5 (low risk)');
  process.exit(0);
}

scanLiquidationRisks().catch(console.error);
