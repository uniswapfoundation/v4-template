import 'dotenv/config';
import { http, createWalletClient, createPublicClient, defineChain, encodeAbiParameters, keccak256, parseEventLogs } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { getContracts, UNICHAIN_SEPOLIA } from './contracts';

// Pyth ETH/USD price feed ID for accurate liquidation pricing
const PYTH_ETH_USD_FEED_ID = '0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace';

// Liquidation bot configuration
const LIQUIDATION_CONFIG = {
  SCAN_INTERVAL: 30000, // 30 seconds between scans
  BATCH_SIZE: 50, // Maximum positions to check per batch
  MIN_HEALTH_FACTOR: 1.05, // 1.05 = 105% (5% buffer above liquidation threshold)
  MAX_CONCURRENT_LIQUIDATIONS: 10, // Maximum concurrent liquidation transactions
  GAS_PRICE_BUFFER: 1.2, // 20% gas price buffer for faster execution
  RETRY_ATTEMPTS: 3, // Number of retry attempts for failed transactions
  PROFIT_THRESHOLD: 0.1, // Minimum profit threshold in USDC to proceed with liquidation
};

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

interface PositionHealth {
  tokenId: number;
  owner: string;
  healthFactor: number;
  isLiquidatable: boolean;
  currentPrice: number;
  margin: number;
  positionSize: number;
  isLong: boolean;
  estimatedProfit: number;
}

interface LiquidationStats {
  totalScanned: number;
  liquidatableFound: number;
  successfulLiquidations: number;
  failedLiquidations: number;
  totalProfit: number;
  errors: string[];
}

class LiquidationBot {
  private contracts: any;
  private poolId: `0x${string}`;
  private isRunning: boolean = false;
  private stats: LiquidationStats = {
    totalScanned: 0,
    liquidatableFound: 0,
    successfulLiquidations: 0,
    failedLiquidations: 0,
    totalProfit: 0,
    errors: []
  };

  constructor() {
    this.contracts = getContracts();
    
    // Generate pool ID
    this.poolId = keccak256(
      encodeAbiParameters(
        [
          { name: 'currency0', type: 'address' },
          { name: 'currency1', type: 'address' },
          { name: 'fee', type: 'uint24' },
          { name: 'tickSpacing', type: 'int24' },
          { name: 'hooks', type: 'address' }
        ],
        [
          this.contracts.mockVETH.address as `0x${string}`,
          this.contracts.mockUSDC.address as `0x${string}`,
          3000,
          60,
          this.contracts.perpsHook.address as `0x${string}`
        ]
      )
    );
  }

  async start() {
    if (this.isRunning) {
      console.log('⚠️ Liquidation bot is already running');
      return;
    }

    console.log('🤖 Starting UniPerp Liquidation Bot');
    console.log('👤 Bot Address:', account.address);
    console.log('🆔 Pool ID:', this.poolId);
    console.log('⏱️ Scan Interval:', LIQUIDATION_CONFIG.SCAN_INTERVAL / 1000, 'seconds');
    console.log('📊 Batch Size:', LIQUIDATION_CONFIG.BATCH_SIZE);
    console.log('🎯 Min Health Factor:', LIQUIDATION_CONFIG.MIN_HEALTH_FACTOR);

    // Setup liquidation configuration if needed
    await this.setupLiquidationConfig();

    this.isRunning = true;

    // Start the monitoring loop
    this.monitoringLoop();

    // Setup graceful shutdown
    process.on('SIGINT', () => {
      console.log('\n🛑 Shutting down liquidation bot...');
      this.stop();
    });

    process.on('SIGTERM', () => {
      console.log('\n🛑 Shutting down liquidation bot...');
      this.stop();
    });
  }

  async stop() {
    this.isRunning = false;
    console.log('📊 Final Bot Statistics:');
    console.log('  Total Positions Scanned:', this.stats.totalScanned);
    console.log('  Liquidatable Positions Found:', this.stats.liquidatableFound);
    console.log('  Successful Liquidations:', this.stats.successfulLiquidations);
    console.log('  Failed Liquidations:', this.stats.failedLiquidations);
    console.log('  Total Profit Earned:', this.stats.totalProfit.toFixed(6), 'USDC');
    if (this.stats.errors.length > 0) {
      console.log('  Recent Errors:', this.stats.errors.slice(-5));
    }
    process.exit(0);
  }

  private async monitoringLoop() {
    while (this.isRunning) {
      try {
        await this.scanAndLiquidate();
      } catch (error) {
        console.error('❌ Error in monitoring loop:', error);
        this.stats.errors.push(String(error).substring(0, 100));
      }

      // Wait for next scan interval
      await new Promise(resolve => setTimeout(resolve, LIQUIDATION_CONFIG.SCAN_INTERVAL));
    }
  }

  private async scanAndLiquidate() {
    console.log('\n🔍 Scanning for liquidatable positions...');
    
    const pythPrice = await fetchPythPrice();
    console.log('📡 Current ETH Price:', pythPrice.toFixed(2), 'USD (Pyth)');

    // Get all active positions to scan
    const positionsToScan = await this.getAllActivePositions();
    
    if (positionsToScan.length === 0) {
      console.log('📊 No active positions found');
      return;
    }

    console.log('📊 Found', positionsToScan.length, 'active positions to scan');

    // Check health of all positions
    const positionHealths = await this.checkPositionHealths(positionsToScan, pythPrice);
    
    // Filter liquidatable positions
    const liquidatablePositions = positionHealths.filter(p => 
      p.isLiquidatable && p.estimatedProfit >= LIQUIDATION_CONFIG.PROFIT_THRESHOLD
    );

    this.stats.totalScanned += positionsToScan.length;
    this.stats.liquidatableFound += liquidatablePositions.length;

    if (liquidatablePositions.length === 0) {
      console.log('✅ All positions are healthy');
      return;
    }

    console.log('🚨 Found', liquidatablePositions.length, 'liquidatable positions');
    
    // Sort by profitability (highest profit first)
    liquidatablePositions.sort((a, b) => b.estimatedProfit - a.estimatedProfit);

    // Display liquidatable positions
    liquidatablePositions.forEach(pos => {
      console.log(`  💀 Position #${pos.tokenId}: Health ${pos.healthFactor.toFixed(3)}, Profit ${pos.estimatedProfit.toFixed(3)} USDC`);
    });

    // Execute liquidations in batches
    await this.executeLiquidations(liquidatablePositions);
  }

  private async getAllActivePositions(): Promise<number[]> {
    try {
      // Scan for active positions by checking a range of token IDs
      const activePositions: number[] = [];
      const maxTokenId = 100; // Adjust based on your system

      for (let tokenId = 1; tokenId <= maxTokenId; tokenId++) {
        try {
          const position = await publicClient.readContract({
            address: this.contracts.positionManager.address,
            abi: this.contracts.positionManager.abi as any,
            functionName: 'getPosition',
            args: [tokenId]
          }) as any;

          // Check if position exists and is active
          if (position.owner !== '0x0000000000000000000000000000000000000000' && position.sizeBase !== 0n) {
            activePositions.push(tokenId);
          }
        } catch (error) {
          // Position doesn't exist or error reading, skip
          continue;
        }
      }

      return activePositions;
    } catch (error) {
      console.error('❌ Error getting active positions:', error);
      return [];
    }
  }

  private async checkPositionHealths(tokenIds: number[], currentPrice: number): Promise<PositionHealth[]> {
    const healthResults: PositionHealth[] = [];

    for (const tokenId of tokenIds) {
      try {
        // Get position details
        const position = await publicClient.readContract({
          address: this.contracts.positionManager.address,
          abi: this.contracts.positionManager.abi as any,
          functionName: 'getPosition',
          args: [tokenId]
        }) as any;

        // Check liquidation status
        const [isLiquidatable, price, healthFactor] = await publicClient.readContract({
          address: this.contracts.liquidationEngine.address,
          abi: this.contracts.liquidationEngine.abi as any,
          functionName: 'isPositionLiquidatable',
          args: [tokenId]
        }) as [boolean, bigint, bigint];

        const positionSize = Number(position.sizeBase) / 1e18;
        const isLong = position.sizeBase > 0n;
        const margin = Number(position.margin) / 1e6;

        // Estimate liquidation profit
        const estimatedProfit = await this.estimateLiquidationProfit(tokenId, positionSize, currentPrice);

        healthResults.push({
          tokenId,
          owner: position.owner,
          healthFactor: Number(healthFactor) / 1e18,
          isLiquidatable,
          currentPrice: Number(price) / 1e18,
          margin,
          positionSize: Math.abs(positionSize),
          isLong,
          estimatedProfit
        });

      } catch (error) {
        console.error(`❌ Error checking position ${tokenId}:`, error);
        continue;
      }
    }

    return healthResults;
  }

  private async estimateLiquidationProfit(tokenId: number, positionSize: number, currentPrice: number): Promise<number> {
    try {
      // Get liquidation configuration
      const config = await publicClient.readContract({
        address: this.contracts.liquidationEngine.address,
        abi: this.contracts.liquidationEngine.abi as any,
        functionName: 'getLiquidationConfig',
        args: [this.poolId]
      }) as any;

      if (!config || !config.isActive) return 0;

      const positionValue = Math.abs(positionSize) * currentPrice;
      const liquidationFee = (positionValue * Number(config.liquidationFeeRate)) / 10000;
      
      // Estimate gas costs (rough approximation)
      const estimatedGasPrice = 20; // gwei
      const estimatedGasLimit = 300000; // gas units
      const ethPrice = currentPrice; // Use ETH price as proxy
      const gasCostUSD = (estimatedGasPrice * estimatedGasLimit * ethPrice) / 1e18;

      return Math.max(0, liquidationFee - gasCostUSD);
    } catch (error) {
      console.error('❌ Error estimating liquidation profit:', error);
      return 0;
    }
  }

  private async executeLiquidations(positions: PositionHealth[]) {
    const batchSize = Math.min(LIQUIDATION_CONFIG.MAX_CONCURRENT_LIQUIDATIONS, positions.length);
    const batches = [];

    for (let i = 0; i < positions.length; i += batchSize) {
      batches.push(positions.slice(i, i + batchSize));
    }

    for (const batch of batches) {
      console.log(`\n⚡ Executing liquidation batch of ${batch.length} positions...`);
      
      const liquidationPromises = batch.map(position => 
        this.liquidatePosition(position.tokenId, position.estimatedProfit)
      );

      const results = await Promise.allSettled(liquidationPromises);
      
      results.forEach((result, index) => {
        if (result.status === 'fulfilled') {
          this.stats.successfulLiquidations++;
          this.stats.totalProfit += batch[index].estimatedProfit;
        } else {
          this.stats.failedLiquidations++;
          console.error(`❌ Liquidation failed for position ${batch[index].tokenId}:`, result.reason);
        }
      });

      // Add delay between batches to avoid overwhelming the network
      if (batches.length > 1) {
        await new Promise(resolve => setTimeout(resolve, 2000));
      }
    }
  }

  private async liquidatePosition(tokenId: number, estimatedProfit: number): Promise<void> {
    let attempts = 0;
    
    while (attempts < LIQUIDATION_CONFIG.RETRY_ATTEMPTS) {
      try {
        console.log(`⚡ Liquidating position #${tokenId} (attempt ${attempts + 1}/${LIQUIDATION_CONFIG.RETRY_ATTEMPTS})`);
        
        const tx = await walletClient.writeContract({
          address: this.contracts.liquidationEngine.address,
          abi: this.contracts.liquidationEngine.abi as any,
          functionName: 'liquidatePosition',
          args: [tokenId]
        });

        console.log(`✅ Liquidation submitted for position #${tokenId}, tx: ${tx}`);
        
        // Wait for confirmation
        const receipt = await publicClient.waitForTransactionReceipt({ hash: tx });
        
        if (receipt.status === 'success') {
          console.log(`🎉 Position #${tokenId} liquidated successfully! Estimated profit: ${estimatedProfit.toFixed(3)} USDC`);
          return;
        } else {
          throw new Error('Transaction failed');
        }

      } catch (error) {
        attempts++;
        console.error(`❌ Liquidation attempt ${attempts} failed for position ${tokenId}:`, error);
        
        if (attempts < LIQUIDATION_CONFIG.RETRY_ATTEMPTS) {
          // Wait before retry
          await new Promise(resolve => setTimeout(resolve, 1000 * attempts));
        }
      }
    }
    
    throw new Error(`Failed to liquidate position ${tokenId} after ${LIQUIDATION_CONFIG.RETRY_ATTEMPTS} attempts`);
  }

  private async setupLiquidationConfig() {
    try {
      console.log('🔧 Checking liquidation configuration...');
      
      const config = await publicClient.readContract({
        address: this.contracts.liquidationEngine.address,
        abi: this.contracts.liquidationEngine.abi as any,
        functionName: 'getLiquidationConfig',
        args: [this.poolId]
      }) as any;

      if (!config.isActive || config.maintenanceMarginRatio === 0n) {
        console.log('⚙️ Setting up liquidation configuration...');
        
        const tx = await walletClient.writeContract({
          address: this.contracts.liquidationEngine.address,
          abi: this.contracts.liquidationEngine.abi as any,
          functionName: 'configureLiquidation',
          args: [
            this.poolId,
            500,  // 5% maintenance margin ratio
            250,  // 2.5% liquidation fee
            250,  // 2.5% insurance fee
            true  // activate liquidations
          ]
        });

        await publicClient.waitForTransactionReceipt({ hash: tx });
        console.log('✅ Liquidation configuration set up successfully');
      } else {
        console.log('✅ Liquidation configuration already active');
        console.log('  Maintenance Margin Ratio:', Number(config.maintenanceMarginRatio) / 100, '%');
        console.log('  Liquidation Fee Rate:', Number(config.liquidationFeeRate) / 100, '%');
        console.log('  Insurance Fee Rate:', Number(config.insuranceFeeRate) / 100, '%');
      }
    } catch (error) {
      console.error('❌ Error setting up liquidation configuration:', error);
    }
  }

  // Manual liquidation method for testing
  async liquidatePositionManually(tokenId: number) {
    try {
      const pythPrice = await fetchPythPrice();
      console.log('📡 Current ETH Price:', pythPrice.toFixed(2), 'USD');

      // Check if position is liquidatable
      const [isLiquidatable, currentPrice, healthFactor] = await publicClient.readContract({
        address: this.contracts.liquidationEngine.address,
        abi: this.contracts.liquidationEngine.abi as any,
        functionName: 'isPositionLiquidatable',
        args: [tokenId]
      }) as [boolean, bigint, bigint];

      console.log(`📊 Position #${tokenId}:`);
      console.log('  Health Factor:', Number(healthFactor) / 1e18);
      console.log('  Is Liquidatable:', isLiquidatable);
      console.log('  Current Price:', Number(currentPrice) / 1e18, 'USD');

      if (!isLiquidatable) {
        console.log('✅ Position is not liquidatable');
        return;
      }

      await this.liquidatePosition(tokenId, 0);
      
    } catch (error) {
      console.error('❌ Error in manual liquidation:', error);
    }
  }
}

// Main execution
async function main() {
  const args = process.argv.slice(2);
  
  if (args.length > 0 && args[0] === 'manual') {
    // Manual liquidation mode
    const tokenId = parseInt(args[1]);
    if (!tokenId || tokenId <= 0) {
      console.log('Usage: bun run liquidationBot.ts manual <tokenId>');
      process.exit(1);
    }
    
    const bot = new LiquidationBot();
    await bot.liquidatePositionManually(tokenId);
    return;
  }
  
  // Start automated liquidation bot
  const bot = new LiquidationBot();
  await bot.start();
}

main().catch(console.error);
