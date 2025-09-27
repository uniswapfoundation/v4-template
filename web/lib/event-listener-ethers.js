const { ethers } = require("ethers");

// Unichain Sepolia configuration
const RPC_URL =
  process.env.UNICHAIN_SEPOLIA_RPC_URL || "https://sepolia.unichain.org";
const POSITION_MANAGER_ADDRESS = "0xD919D9FA466fD3e88640F97700640fbBb3214eB2";

// PositionOpened event ABI
const POSITION_OPENED_ABI = [
  "event PositionOpened(uint256 indexed tokenId, address indexed owner, bytes32 indexed marketId, int256 sizeBase, uint256 entryPrice, uint256 margin)",
];

// PositionClosed event ABI
const POSITION_CLOSED_ABI = [
  "event PositionClosed(uint256 indexed tokenId, address indexed owner, int256 pnl)",
];

class EventListener {
  constructor() {
    this.provider = new ethers.JsonRpcProvider(RPC_URL);
    this.contract = new ethers.Contract(
      POSITION_MANAGER_ADDRESS,
      [...POSITION_OPENED_ABI, ...POSITION_CLOSED_ABI],
      this.provider
    );
    this.subscribers = new Set();
    this.isListening = false;
    this.listeners = [];
  }

  // Subscribe to position events
  subscribe(callback) {
    this.subscribers.add(callback);

    // Start listening if not already started
    if (!this.isListening) {
      this.startListening();
    }
  }

  // Unsubscribe from position events
  unsubscribe(callback) {
    this.subscribers.delete(callback);
  }

  // Start listening to blockchain events
  async startListening() {
    if (this.isListening) return;

    this.isListening = true;
    console.log("🔍 Starting event listener for PositionManager...");

    try {
      // Listen to PositionOpened events
      const openedListener = (
        tokenId,
        owner,
        marketId,
        sizeBase,
        entryPrice,
        margin,
        event
      ) => {
        const positionEvent = this.parsePositionOpenedEvent({
          args: { tokenId, owner, marketId, sizeBase, entryPrice, margin },
          blockNumber: event.blockNumber,
          transactionHash: event.transactionHash,
        });
        this.notifySubscribers(positionEvent);
      };

      // Listen to PositionClosed events
      const closedListener = (tokenId, owner, pnl, event) => {
        const positionEvent = this.parsePositionClosedEvent({
          args: { tokenId, owner, pnl },
          blockNumber: event.blockNumber,
          transactionHash: event.transactionHash,
        });
        this.notifySubscribers(positionEvent);
      };

      // Set up event listeners
      this.contract.on("PositionOpened", openedListener);
      this.contract.on("PositionClosed", closedListener);

      // Store listeners for cleanup
      this.listeners = [
        { event: "PositionOpened", listener: openedListener },
        { event: "PositionClosed", listener: closedListener },
      ];

      console.log("✅ Event listeners started successfully");
    } catch (error) {
      console.error("❌ Error starting event listener:", error);
      this.isListening = false;
    }
  }

  // Parse PositionOpened event
  parsePositionOpenedEvent(log) {
    const { args, blockNumber, transactionHash } = log;

    const sizeBase = BigInt(args.sizeBase.toString());
    const side = sizeBase > 0n ? "long" : "short";

    return {
      type: "position_opened",
      tokenId: args.tokenId.toString(),
      owner: args.owner,
      marketId: args.marketId,
      sizeBase: args.sizeBase.toString(),
      entryPrice: args.entryPrice.toString(),
      margin: args.margin.toString(),
      side,
      timestamp: new Date().toISOString(),
      blockNumber: blockNumber,
      transactionHash: transactionHash,
    };
  }

  // Parse PositionClosed event
  parsePositionClosedEvent(log) {
    const { args, blockNumber, transactionHash } = log;

    return {
      type: "position_closed",
      tokenId: args.tokenId.toString(),
      owner: args.owner,
      marketId: "", // Not available in closed event
      sizeBase: "0", // Not available in closed event
      entryPrice: "0", // Not available in closed event
      margin: "0", // Not available in closed event
      pnl: args.pnl.toString(),
      side: "closed",
      timestamp: new Date().toISOString(),
      blockNumber: blockNumber,
      transactionHash: transactionHash,
    };
  }

  // Notify all subscribers
  notifySubscribers(event) {
    console.log(
      `📊 New position event: ${event.type} - ${event.side} - Token ID: ${event.tokenId}`
    );
    this.subscribers.forEach((callback) => {
      try {
        callback(event);
      } catch (error) {
        console.error("Error in event callback:", error);
      }
    });
  }

  // Stop listening and cleanup
  stop() {
    if (this.listeners.length > 0) {
      this.listeners.forEach(({ event, listener }) => {
        this.contract.off(event, listener);
      });
      this.listeners = [];
    }
    this.isListening = false;
    this.subscribers.clear();
    console.log("🛑 Event listener stopped");
  }

  // Get current status
  getStatus() {
    return {
      isListening: this.isListening,
      subscriberCount: this.subscribers.size,
      contractAddress: POSITION_MANAGER_ADDRESS,
      chainId: 1301,
    };
  }
}

// Export singleton instance
const eventListener = new EventListener();

// Graceful shutdown
process.on("SIGINT", () => {
  console.log("🛑 Shutting down event listener...");
  eventListener.stop();
  process.exit(0);
});

process.on("SIGTERM", () => {
  console.log("🛑 Shutting down event listener...");
  eventListener.stop();
  process.exit(0);
});

module.exports = { eventListener };
