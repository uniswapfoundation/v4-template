# UniPerp Scripts Summary

This document provides a comprehensive overview of all the scripts available in the UniPerp perpetual futures trading system, organized by functionality.

## 🚀 Core Trading Scripts (With Pyth Integration)

### Position Opening Scripts

#### `openLongCorrectCalculation.ts`
**Purpose**: Open leveraged LONG positions with real-time Pyth price integration
**Features**:
- ✅ Real-time ETH price from Pyth Network API
- ✅ Automatic vAMM rebalancing after position opening
- ✅ Proper leverage and margin calculations
- ✅ Comprehensive position analysis and PnL projections

**Usage**:
```bash
bun run examples/openLongCorrectCalculation.ts <margin> <leverage>
# Example: bun run examples/openLongCorrectCalculation.ts 200 3
```

#### `openShortCorrectCalculation.ts`
**Purpose**: Open leveraged SHORT positions with real-time Pyth price integration
**Features**:
- ✅ Real-time ETH price from Pyth Network API
- ✅ Automatic vAMM rebalancing after position opening
- ✅ Proper leverage and margin calculations for short positions
- ✅ Comprehensive position analysis and PnL projections

**Usage**:
```bash
bun run examples/openShortCorrectCalculation.ts <margin> <leverage>
# Example: bun run examples/openShortCorrectCalculation.ts 150 4
```

### Position Closing Scripts

#### `closePositionWithPyth.ts`
**Purpose**: Close positions (partial or full) with real-time Pyth pricing
**Features**:
- ✅ Real-time exit pricing using Pyth Network
- ✅ Partial closure support (any percentage 1-100%)
- ✅ Full position closure (100%)
- ✅ Automatic vAMM rebalancing after closure
- ✅ Detailed PnL calculations and realized profit/loss

**Usage**:
```bash
# Close 100% of position
bun run examples/closePositionWithPyth.ts <tokenId>
# Close partial position
bun run examples/closePositionWithPyth.ts <tokenId> <percentage>

# Examples:
bun run examples/closePositionWithPyth.ts 5        # Close 100% of position #5
bun run examples/closePositionWithPyth.ts 3 50     # Close 50% of position #3
bun run examples/closePositionWithPyth.ts 7 25     # Close 25% of position #7
```

## 📊 Portfolio Management Scripts

#### `portfolioOverviewFixed.ts`
**Purpose**: Comprehensive portfolio overview with all positions and balances
**Features**:
- ✅ Real-time mark price using current vAMM state
- ✅ All active positions with detailed metrics
- ✅ Portfolio-wide PnL calculations
- ✅ Risk assessment (leverage warnings, underwater positions)
- ✅ Account balance breakdown (free vs margin used)

**Usage**:
```bash
bun run examples/portfolioOverviewFixed.ts
```

#### `quickPortfolio.ts`
**Purpose**: Quick portfolio snapshot
**Features**:
- ✅ Summary of key portfolio metrics
- ✅ Total PnL and position count
- ✅ Balance overview

**Usage**:
```bash
bun run examples/quickPortfolio.ts
```

#### `showPositions.ts`
**Purpose**: Display detailed information for specific positions
**Features**:
- ✅ Individual position analysis
- ✅ Current PnL calculations
- ✅ Position health metrics

**Usage**:
```bash
bun run examples/showPositions.ts <tokenId>
# Example: bun run examples/showPositions.ts 5
```

## 🔧 Utility & Testing Scripts

#### `testPythPrice.ts`
**Purpose**: Test Pyth Network price feed integration
**Features**:
- ✅ Fetch real-time ETH/USD price from Pyth
- ✅ Display price feed metadata (confidence, publish time, EMA)
- ✅ Calculate virtual reserve scenarios for different liquidity levels
- ✅ Price feed validation and fallback testing

**Usage**:
```bash
bun run examples/testPythPrice.ts
```

## 🏗️ System Setup & Management Scripts

#### `setupNewSystemComplete.ts`
**Purpose**: Complete system initialization and setup
**Features**:
- ✅ Market registration across all managers
- ✅ Authorization setup between contracts
- ✅ Initial vAMM configuration
- ✅ Pool initialization

**Usage**:
```bash
bun run examples/setupNewSystemComplete.ts
```

## 🧪 Experimental Scripts

#### `openLongViaSwap.ts`
**Purpose**: Experimental position opening via Uniswap V4 swap with hookData
**Status**: ⚠️ Experimental - encounters price limit issues
**Features**:
- ⚠️ Attempts to open positions through swap interface
- ⚠️ Uses hookData for position parameters
- ⚠️ Currently facing architectural challenges with price limits

**Usage**:
```bash
bun run examples/openLongViaSwap.ts <margin> <leverage> <maxSlippage>
# Note: This is experimental and may not work reliably
```

## 📈 Key Features Across All Scripts

### 🌐 Pyth Network Integration
All core trading scripts now integrate with Pyth Network for real-time price feeds:
- **Feed ID**: `0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace`
- **Current ETH Price**: ~$4024 (vs old hardcoded $2000)
- **Automatic Fallback**: Falls back to $2000 if Pyth API fails
- **Price Metadata**: Includes confidence intervals, publish times, and EMA prices

### ⚖️ Automatic vAMM Rebalancing
After each position operation, scripts automatically rebalance virtual reserves:
- **Target Liquidity**: 1.2M USDC virtual quote
- **Dynamic Base Calculation**: Based on real Pyth price
- **Price Accuracy**: Maintains mark price aligned with real market conditions

### 📊 Comprehensive Analytics
All scripts provide detailed analytics:
- **Position Metrics**: Size, margin, leverage, entry price, current price
- **PnL Calculations**: Unrealized and realized profit/loss
- **Risk Assessment**: Leverage warnings and position health
- **Transaction Details**: Hashes, block numbers, gas usage

## 🎯 Recommended Workflow

### 1. **System Setup** (One-time)
```bash
# Deploy contracts (if needed)
make deploy-production-miner-unichain-sepolia

# Setup system
bun run examples/setupNewSystemComplete.ts
```

### 2. **Trading Operations**
```bash
# Open positions
bun run examples/openLongCorrectCalculation.ts 200 3   # Long with 200 USDC, 3x leverage
bun run examples/openShortCorrectCalculation.ts 150 4  # Short with 150 USDC, 4x leverage

# Monitor portfolio
bun run examples/portfolioOverviewFixed.ts

# Close positions
bun run examples/closePositionWithPyth.ts 5 50  # Close 50% of position #5
```

### 3. **Monitoring & Analysis**
```bash
# Check specific positions
bun run examples/showPositions.ts 3

# Test price feeds
bun run examples/testPythPrice.ts

# Quick portfolio check
bun run examples/quickPortfolio.ts
```

## 🔑 Environment Configuration

All scripts require proper `.env` configuration:
```bash
PRIVATE_KEY=your_private_key_here
RPC_URL=https://sepolia.unichain.org
UNICHAIN_SEPOLIA_RPC_URL=https://sepolia.unichain.org
CHAIN_ID=1301
DEPLOYMENT_NETWORK=unichain-sepolia
```

## 📊 Current System Status

- **✅ Core Functionality**: Fully operational with real-time pricing
- **✅ Position Management**: Complete CRUD operations for positions
- **✅ Portfolio Analytics**: Comprehensive reporting and risk assessment
- **✅ Price Integration**: Real-time Pyth Network price feeds
- **✅ vAMM Management**: Automatic rebalancing and price stability
- **⚠️ Swap Integration**: Experimental feature with known limitations

## 🚀 Production Readiness

The UniPerp system is **production-ready** for perpetual futures trading with:
- **Institutional-grade pricing** via Pyth Network
- **Flexible position management** (partial/full closures)
- **Real-time risk assessment** and portfolio analytics
- **Automatic market making** with balanced virtual reserves
- **Comprehensive transaction tracking** and audit trails

---

*Last Updated: September 28, 2025*
*System Version: v1.0 with Pyth Integration*
