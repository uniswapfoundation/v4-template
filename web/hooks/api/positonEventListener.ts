import 'dotenv/config';
import { createPublicClient, http, defineChain, parseAbiItem, decodeEventLog } from 'viem';
import { getContracts, UNICHAIN_SEPOLIA } from '@/lib/core';
import { WebSocketServer, WebSocket } from 'ws';

const RPC_URL = process.env.RPC_URL || process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org';
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);

// WebSocket server for real-time updates to UI
const WS_PORT = 8080;

// Position Manager Event ABIs
const POSITION_OPENED_EVENT = parseAbiItem('event PositionOpened(uint256 indexed tokenId, address indexed owner, bytes32 indexed marketId, int256 sizeBase, uint256 entryPrice, uint256 margin)');
const POSITION_CLOSED_EVENT = parseAbiItem('event PositionClosed(uint256 indexed tokenId, address indexed owner, int256 pnl)');
const POSITION_UPDATED_EVENT = parseAbiItem('event PositionUpdated(uint256 indexed tokenId, int256 newSizeBase, uint256 newMargin)');

export interface PositionEvent {
  tokenId: string;
  trader: string;
  market: string;
  side: 'Long' | 'Short';
  size: string;
  entryPrice: string;
  markPrice?: string;
  margin: string;
  leverage: string;
  pnl?: string;
  pnlPercentage?: string;
  timestamp: Date;
  transactionHash: string;
  blockNumber: number;
  status: 'Open' | 'Closed';
}

class PositionEventListener {
  private client: any;
  private contracts: any;
  private wsServer: WebSocketServer;
  private wsClients: Set<WebSocket> = new Set();
  private openPositions: Map<string, PositionEvent> = new Map();

  constructor() {
    const chain = defineChain({ 
      id: CHAIN_ID, 
      name: 'UnichainSepolia', 
      nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 }, 
      rpcUrls: { 
        default: { http: [RPC_URL] }, 
        public: { http: [RPC_URL] } 
      } 
    });

    this.client = createPublicClient({
      chain,
      transport: http(RPC_URL),
      pollingInterval: 2000,
    });

    this.contracts = getContracts(CHAIN_ID);

    // Setup WebSocket server
    this.wsServer = new WebSocketServer({ port: WS_PORT });
    this.setupWebSocketServer();
  }

  private setupWebSocketServer() {
    console.log(`WebSocket server started on port ${WS_PORT}`);
    
    this.wsServer.on('connection', (ws: WebSocket) => {
      console.log('🔌 New UI client connected');
      this.wsClients.add(ws);

      // Send current open positions on connection
      this.sendOpenPositions(ws);

      ws.on('close', () => {
        console.log('🔌 UI client disconnected');
        this.wsClients.delete(ws);
      });

      ws.on('error', (error: any) => {
        console.error('WebSocket error:', error);
        this.wsClients.delete(ws);
      });
    });
  }

  private getMarketName(marketId: string): string {
    // Map market IDs to readable names
    const marketMap: { [key: string]: string } = {
      '0xb914c28d57aab1df4d75341ad953e33c214f76fb01305ad81ef741049579383e': 'VETH/USDC',
      //'0xdb86d006b7f5ba7afb160f08da976bf53d7254e25da80f1dda0a5d36d26d656d': 'VETH/USDC',
    };
    
    const name = marketMap[marketId];
    if (!name) {
      console.log(`⚠️ Unknown marketId: ${marketId}`);
      return `Market-${marketId.slice(0, 8)}`;
    }
    return name;
  }

  private broadcastToClients(message: any) {
    const jsonMessage = JSON.stringify(message);
    this.wsClients.forEach(client => {
      if (client.readyState === WebSocket.OPEN) {
        client.send(jsonMessage);
      }
    });
  }

  private async sendOpenPositions(ws: WebSocket) {
    try {
      const positions = Array.from(this.openPositions.values());
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({
          type: 'INITIAL_POSITIONS',
          data: positions
        }));
      }
    } catch (error) {
      console.error('Error sending open positions:', error);
    }
  }

  async startListening() {
    console.log('🎧 Starting to listen for position events...');
    console.log('📡 Monitoring PositionManager:', this.contracts.positionManager.address);
    console.log(`🌐 UI can connect to WebSocket at ws://localhost:${WS_PORT}`);

    // Load existing open positions
    await this.loadOpenPositions();

    // Watch for new PositionOpened events
    const unwatchOpened = this.client.watchContractEvent({
      address: this.contracts.positionManager.address,
      abi: [POSITION_OPENED_EVENT],
      eventName: 'PositionOpened',
      onLogs: (logs: any[]) => {
        logs.forEach(log => this.handlePositionOpened(log));
      },
    });

    // Watch for PositionUpdated events
    const unwatchUpdated = this.client.watchContractEvent({
      address: this.contracts.positionManager.address,
      abi: [POSITION_UPDATED_EVENT],
      eventName: 'PositionUpdated',
      onLogs: (logs: any[]) => {
        logs.forEach(log => this.handlePositionUpdated(log));
      },
    });

    // Watch for PositionClosed events
    const unwatchClosed = this.client.watchContractEvent({
      address: this.contracts.positionManager.address,
      abi: [POSITION_CLOSED_EVENT],
      eventName: 'PositionClosed',
      onLogs: (logs: any[]) => {
        logs.forEach(log => this.handlePositionClosed(log));
      },
    });

    console.log('✅ Position event listener is running successfully!');
    console.log(`🌐 WebSocket server is ready for UI connections at ws://localhost:${WS_PORT}`);
    console.log('\nPress Ctrl+C to stop the listener...');

    // Show current status every 10 seconds
    setInterval(() => {
      console.log(`📊 Currently tracking ${this.openPositions.size} open positions`);
    }, 10000);

    // Return cleanup function
    return () => {
      unwatchOpened();
      unwatchUpdated();
      unwatchClosed();
    };
  }

  private async handlePositionOpened(log: any) {
    try {
      console.log('📍 Processing PositionOpened event:', log.transactionHash);
      const { args } = log;
      const tokenId = args.tokenId;
      
      // Read position directly from contract to get accurate data (same as showPositions.ts)
      const position = await this.client.readContract({
        address: this.contracts.positionManager.address,
        abi: this.contracts.positionManager.abi as any,
        functionName: 'getPosition',
        args: [tokenId]
      }) as any;

      // Use the exact same scaling as showPositions.ts
      const sizeBase = Number(position.sizeBase) / 1e18;
      const entryPrice = Number(position.entryPrice) / 1e18;  // Correct scaling from showPositions.ts
      const margin = Number(position.margin) / 1e6;
      const isLong = Number(position.sizeBase) > 0;
      
      // Try to get mark price (same as showPositions.ts)
      let markPriceFormatted = entryPrice; // Default to entry price
      try {
        const markPrice = await this.client.readContract({
          address: this.contracts.fundingOracle.address,
          abi: this.contracts.fundingOracle.abi as any,
          functionName: 'getMarkPrice',
          args: ['0xdb86d006b7f5ba7afb160f08da976bf53d7254e25da80f1dda0a5d36d26d656d'] // Same pool ID as showPositions
        }) as bigint;
        markPriceFormatted = Number(markPrice) / 1e18;
      } catch (error) {
        console.warn('⚠️ Could not fetch mark price, using entry price');
      }
      
      const notionalValue = Math.abs(sizeBase) * entryPrice;
      const leverage = notionalValue / margin;

      // Calculate PnL (same logic as showPositions.ts)
      let unrealizedPnL = 0;
      if (isLong) {
        unrealizedPnL = Math.abs(sizeBase) * (markPriceFormatted - entryPrice);
      } else {
        unrealizedPnL = Math.abs(sizeBase) * (entryPrice - markPriceFormatted);
      }
      const pnlPercent = (unrealizedPnL / margin) * 100;

      const positionEvent: PositionEvent = {
        tokenId: tokenId.toString(),
        trader: position.owner,
        market: this.getMarketName(position.marketId),
        side: isLong ? 'Long' : 'Short',
        size: Math.abs(sizeBase).toFixed(4),
        entryPrice: entryPrice.toFixed(2),  // Now shows correct price like showPositions
        markPrice: markPriceFormatted.toFixed(2),
        margin: margin.toFixed(2),
        leverage: leverage.toFixed(2) + 'x',
        timestamp: new Date(Number(position.openedAt) * 1000),
        transactionHash: log.transactionHash,
        blockNumber: Number(log.blockNumber),
        status: 'Open',
        pnl: unrealizedPnL >= 0 ? `+${unrealizedPnL.toFixed(2)}` : unrealizedPnL.toFixed(2),
        pnlPercentage: `(${pnlPercent >= 0 ? '+' : ''}${pnlPercent.toFixed(2)}%)`,
      };

      this.openPositions.set(positionEvent.tokenId, positionEvent);

      console.log(`✅ New ${positionEvent.side.toUpperCase()} position opened:`);
      console.log(`  Token ID: ${positionEvent.tokenId}`);
      console.log(`  Entry Price: ${positionEvent.entryPrice} USDC/VETH`);
      console.log(`  Size: ${positionEvent.size} VETH`);
      console.log(`  Margin: ${positionEvent.margin} USDC`);
      console.log(`  Leverage: ${positionEvent.leverage}`);

      this.broadcastToClients({
        type: 'POSITION_OPENED',
        data: positionEvent
      });

    } catch (error) {
      console.error('Error processing PositionOpened event:', error);
    }
  }

  private async handlePositionUpdated(log: any) {
    try {
      console.log('📝 Processing PositionUpdated event:', log.transactionHash);
      const { args } = log;
      const tokenId = args.tokenId;
      
      // Read updated position from contract (same approach as showPositions)
      const position = await this.client.readContract({
        address: this.contracts.positionManager.address,
        abi: this.contracts.positionManager.abi as any,
        functionName: 'getPosition',
        args: [tokenId]
      }) as any;

      const sizeBase = Number(position.sizeBase) / 1e18;
      const margin = Number(position.margin) / 1e6;
      const isLong = Number(position.sizeBase) > 0;
      
      if (this.openPositions.has(tokenId.toString())) {
        const existingPosition = this.openPositions.get(tokenId.toString())!;
        existingPosition.size = Math.abs(sizeBase).toFixed(4);
        existingPosition.margin = margin.toFixed(2);
        existingPosition.side = isLong ? 'Long' : 'Short';
        
        // Recalculate leverage
        const entryPrice = parseFloat(existingPosition.entryPrice);
        const leverage = (Math.abs(sizeBase) * entryPrice) / margin;
        existingPosition.leverage = leverage.toFixed(2) + 'x';
        
        console.log(`📝 Position ${tokenId} updated`);
        console.log(`  New Size: ${existingPosition.size} VETH`);
        console.log(`  New Margin: ${existingPosition.margin} USDC`);
        
        this.broadcastToClients({
          type: 'POSITION_UPDATED',
          data: existingPosition
        });
      }

    } catch (error) {
      console.error('Error processing PositionUpdated event:', error);
    }
  }

  private async handlePositionClosed(log: any) {
    try {
      console.log('🔒 Processing PositionClosed event:', log.transactionHash);
      const { args } = log;
      const tokenId = args.tokenId.toString();
      
      if (this.openPositions.has(tokenId)) {
        const position = this.openPositions.get(tokenId)!;
        position.status = 'Closed';
        const pnlValue = Number(args.pnl) / 1e6;
        position.pnl = pnlValue >= 0 ? `+${pnlValue.toFixed(2)}` : pnlValue.toFixed(2);
        position.timestamp = new Date();
        
        const pnlPercentage = (pnlValue / parseFloat(position.margin)) * 100;
        position.pnlPercentage = pnlPercentage >= 0 ? `(+${pnlPercentage.toFixed(2)}%)` : `(${pnlPercentage.toFixed(2)}%)`;
        
        console.log(`❌ Position ${tokenId} closed:`);
        console.log(`  PnL: ${position.pnl} USDC`);
        console.log(`  PnL %: ${position.pnlPercentage}`);
        
        // Remove from open positions
        this.openPositions.delete(tokenId);
        
        this.broadcastToClients({
          type: 'POSITION_CLOSED',
          data: position
        });
      }
    } catch (error) {
      console.error('Error processing PositionClosed event:', error);
    }
  }

  private async loadOpenPositions() {
    try {
      console.log('📚 Loading existing open positions...');
      
      // First, try to load from specific wallet if configured
      const walletAddress = process.env.WALLET_ADDRESS || process.env.PUBLIC_KEY;
      
      if (walletAddress) {
        console.log(`🔍 Checking positions for wallet: ${walletAddress}`);
        
        try {
          // Use getUserPositions like showPositions.ts
          const userPositions = await this.client.readContract({
            address: this.contracts.positionManager.address,
            abi: this.contracts.positionManager.abi as any,
            functionName: 'getUserPositions',
            args: [walletAddress]
          }) as bigint[];

          console.log(`  Found ${userPositions.length} position(s)`);

          if (userPositions.length > 0) {
            // Get current mark price (same as showPositions.ts)
            let markPriceFormatted = 0;
            try {
              const markPrice = await this.client.readContract({
                address: this.contracts.fundingOracle.address,
                abi: this.contracts.fundingOracle.abi as any,
                functionName: 'getMarkPrice',
                args: ['0xdb86d006b7f5ba7afb160f08da976bf53d7254e25da80f1dda0a5d36d26d656d']
              }) as bigint;
              markPriceFormatted = Number(markPrice) / 1e18;
              console.log(`📊 Current Mark Price: ${markPriceFormatted.toFixed(2)} USDC/VETH`);
            } catch (error) {
              console.warn('⚠️ Could not fetch mark price');
            }

            // Process each position (same as showPositions.ts)
            for (const tokenId of userPositions) {
              try {
                const position = await this.client.readContract({
                  address: this.contracts.positionManager.address,
                  abi: this.contracts.positionManager.abi as any,
                  functionName: 'getPosition',
                  args: [tokenId]
                }) as any;

                // Use exact same scaling as showPositions.ts
                const sizeBase = Number(position.sizeBase) / 1e18;
                const entryPrice = Number(position.entryPrice) / 1e18;
                const margin = Number(position.margin) / 1e6;
                const isLong = Number(position.sizeBase) > 0;
                const notionalValue = Math.abs(sizeBase) * entryPrice;
                const leverage = notionalValue / margin;

                // Use mark price if available, otherwise use entry price
                const currentPrice = markPriceFormatted || entryPrice;

                // Calculate PnL (same as showPositions.ts)
                let unrealizedPnL = 0;
                if (isLong) {
                  unrealizedPnL = Math.abs(sizeBase) * (currentPrice - entryPrice);
                } else {
                  unrealizedPnL = Math.abs(sizeBase) * (entryPrice - currentPrice);
                }
                const pnlPercent = (unrealizedPnL / margin) * 100;

                const positionEvent: PositionEvent = {
                  tokenId: tokenId.toString(),
                  trader: position.owner,
                  market: this.getMarketName(position.marketId),
                  side: isLong ? 'Long' : 'Short',
                  size: Math.abs(sizeBase).toFixed(4),
                  entryPrice: entryPrice.toFixed(2),
                  markPrice: currentPrice.toFixed(2),
                  margin: margin.toFixed(2),
                  leverage: leverage.toFixed(2) + 'x',
                  pnl: unrealizedPnL >= 0 ? `+${unrealizedPnL.toFixed(2)}` : unrealizedPnL.toFixed(2),
                  pnlPercentage: `(${pnlPercent >= 0 ? '+' : ''}${pnlPercent.toFixed(2)}%)`,
                  timestamp: new Date(Number(position.openedAt) * 1000),
                  transactionHash: '',
                  blockNumber: 0,
                  status: 'Open'
                };

                this.openPositions.set(positionEvent.tokenId, positionEvent);
                
                console.log(`✅ Loaded position #${tokenId}:`);
                console.log(`  Side: ${positionEvent.side}`);
                console.log(`  Size: ${positionEvent.size} VETH`);
                console.log(`  Entry Price: ${positionEvent.entryPrice} USDC/VETH`);
                console.log(`  Current PnL: ${positionEvent.pnl} USDC ${positionEvent.pnlPercentage}`);

              } catch (error) {
                console.error(`Error loading position ${tokenId}:`, error);
              }
            }
          }
        } catch (error) {
          console.error('Error fetching user positions:', error);
        }
      } else {
        console.log('⚠️ No wallet address configured in .env (WALLET_ADDRESS)');
      }

      // Also check recent events
      const currentBlock = await this.client.getBlockNumber();
      const fromBlock = currentBlock - BigInt(5000);

      console.log(`\n📋 Checking recent events from block ${fromBlock} to ${currentBlock}`);

      const logs = await this.client.getLogs({
        address: this.contracts.positionManager.address,
        fromBlock,
        toBlock: 'latest',
      });

      console.log(`  Found ${logs.length} total logs`);

      let openedCount = 0;
      for (const log of logs) {
        try {
          const decoded = decodeEventLog({
            abi: [POSITION_OPENED_EVENT],
            data: log.data,
            topics: log.topics,
          });
          
          if (decoded.eventName === 'PositionOpened') {
            openedCount++;
            // Only process if not already loaded from getUserPositions
            const tokenId = (decoded.args as any).tokenId.toString();
            if (!this.openPositions.has(tokenId)) {
              await this.handlePositionOpened({ ...log, args: decoded.args });
            }
          }
        } catch {
          // Not a PositionOpened event
        }
      }

      console.log(`  Found ${openedCount} PositionOpened events`);
      console.log(`\n✅ Loaded ${this.openPositions.size} total open positions`);

    } catch (error) {
      console.error('Error loading existing positions:', error);
    }
  }

  async stop() {
    console.log('🛑 Stopping position event listener...');
    this.wsServer.close();
    this.wsClients.forEach(client => client.close());
    console.log('👋 Position event listener stopped');
  }
}

// If running as standalone script
if (require.main === module) {
  const listener = new PositionEventListener();

  listener.startListening().then(() => {
    console.log('✅ Position event listener is running');
    console.log('🎧 Listening for position events...');
    console.log(`🌐 UI WebSocket server running on ws://localhost:${WS_PORT}`);
  });

  // Handle graceful shutdown
  process.on('SIGINT', async () => {
    console.log('\n⚠️ Received SIGINT, shutting down gracefully...');
    await listener.stop();
    process.exit(0);
  });
}

export default PositionEventListener;