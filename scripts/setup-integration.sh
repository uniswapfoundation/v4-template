#!/bin/bash

# Quick Setup Script for Unichain Sepolia Integration
# This script sets up the development environment for the perpetual futures platform

echo "🚀 Setting up Unichain Sepolia Perpetual Futures Integration Environment"
echo "=================================================================="

# Check if we're in the right directory
if [ ! -f "foundry.toml" ]; then
    echo "❌ Error: Please run this script from the project root directory"
    exit 1
fi

# Check for required tools
echo "📋 Checking required tools..."

# Check for Node.js/npm
if ! command -v npm &> /dev/null; then
    echo "❌ npm is required but not installed. Please install Node.js"
    exit 1
fi
echo "✅ npm found"

# Check for Bun (optional but recommended)
if command -v bun &> /dev/null; then
    echo "✅ bun found (recommended)"
    USE_BUN=true
else
    echo "⚠️  bun not found, using npm (consider installing bun for faster execution)"
    USE_BUN=false
fi

# Check for forge
if ! command -v forge &> /dev/null; then
    echo "❌ forge is required but not installed. Please install Foundry"
    exit 1
fi
echo "✅ forge found"

# Install dependencies
echo ""
echo "📦 Installing dependencies..."
cd examples

if [ "$USE_BUN" = true ]; then
    bun install
else
    npm install
fi

cd ..

# Compile contracts to generate ABIs
echo ""
echo "🔨 Compiling contracts to generate ABIs..."
forge build

if [ $? -ne 0 ]; then
    echo "❌ Contract compilation failed"
    exit 1
fi
echo "✅ Contracts compiled successfully"

# Check if .env file exists
cd examples
if [ ! -f ".env" ]; then
    echo ""
    echo "📝 Creating .env template..."
    cat > .env << EOF
# Network Configuration
RPC_URL=https://sepolia.unichain.org
CHAIN_ID=1301
UNICHAIN_SEPOLIA_RPC_URL=https://sepolia.unichain.org

# Private Key (without 0x prefix)
# IMPORTANT: Replace with your actual private key for testing
PRIVATE_KEY=your_private_key_here

# Optional: Custom RPC endpoints
# RPC_URL=https://your-custom-rpc-endpoint
EOF
    echo "✅ .env template created at examples/.env"
    echo "⚠️  IMPORTANT: Edit examples/.env and add your private key before testing"
else
    echo "✅ .env file already exists"
fi

# Display contract addresses
echo ""
echo "📋 Deployed Contract Addresses (Unichain Sepolia):"
echo "=================================================="
echo "MockUSDC:         0x90d44f495BBE67c38479180FA6Fe8f9c4a7a6B1B"
echo "MockVETH:         0xa339cAe8022c9B4703698a5F5a7FedC2533e8622"
echo "MarginAccount:    0x079c1fBFd3B1069015e4C568722a08df8A9E5FB9"
echo "PerpsRouter:      0x1Df5f5AaBCd4873976E53304eB2F49A36060573A"
echo "PerpsHook:        0x67015e8d82DB9f1B866217788118FEAC99689Ac8"
echo "FundingOracle:    0xC2E938Abe91daCc98E4872bC273c86C459D8753A"
echo "LiquidationEngine: 0x53DFE63cDf607957C37DC8340514F08bDfF7343d"
echo "PoolManager:      0x00B036B58a818B1BC34d502D3fE730Db729e62AC (Uniswap V4)"

# Display available scripts
echo ""
echo "🛠  Available Integration Scripts:"
echo "================================="
if [ "$USE_BUN" = true ]; then
    echo "Pool Management:"
    echo "  bun run createPool.ts              # Create VETH-USDC pool"
    echo "  bun run addLiquidity.ts <poolId>   # Add liquidity to pool"
    echo ""
    echo "Margin Operations:"
    echo "  bun run marginOperations.ts deposit 1000   # Deposit 1000 USDC"
    echo "  bun run marginOperations.ts withdraw 500   # Withdraw 500 USDC"
    echo ""
    echo "Trading Operations:"
    echo "  bun run openLong.ts [margin] [leverage]    # Open long position"
    echo "  bun run openShort.ts [margin] [leverage]   # Open short position"
    echo "  bun run closePosition.ts <positionId>      # Close position"
    echo ""
    echo "Information Queries:"
    echo "  bun run getPosition.ts <positionId>        # Get position details"
    echo "  bun run getMarkPrice.ts                    # Get current mark price"
else
    echo "Pool Management:"
    echo "  npm run create-pool                        # Create VETH-USDC pool"
    echo "  npm run add-liquidity <poolId>             # Add liquidity to pool"
    echo ""
    echo "Margin Operations:"
    echo "  npm run margin-operations deposit 1000     # Deposit 1000 USDC"
    echo "  npm run margin-operations withdraw 500     # Withdraw 500 USDC"
    echo ""
    echo "Trading Operations:"
    echo "  npm run open:long [margin] [leverage]      # Open long position"
    echo "  npm run open:short [margin] [leverage]     # Open short position"
    echo "  npm run close:position <positionId>        # Close position"
    echo ""
    echo "Information Queries:"
    echo "  npm run get:position <positionId>          # Get position details"
    echo "  npm run get:mark                           # Get current mark price"
fi

echo ""
echo "📚 Documentation:"
echo "=================="
echo "Integration Guide: docs/integration/README.md"
echo "Contract Addresses: deployments.json"
echo "Contract ABIs: out/<ContractName>.sol/<ContractName>.json"

echo ""
echo "🎯 Quick Start Workflow:"
echo "========================"
echo "1. Edit examples/.env with your private key"
echo "2. Ensure you have ETH for gas on Unichain Sepolia"
echo "3. Get test USDC and VETH tokens (if not already funded)"
echo "4. Create a pool: create-pool script"
echo "5. Add liquidity: add-liquidity script"
echo "6. Start trading: margin operations → open positions"

echo ""
echo "⚠️  Important Notes:"
echo "==================="
echo "• This is a testnet deployment - use only test funds"
echo "• Private keys should never be committed to version control"
echo "• Monitor gas prices and set appropriate limits"
echo "• Test thoroughly before any mainnet deployment"

echo ""
echo "✅ Setup completed successfully!"
echo "📖 Read docs/integration/README.md for detailed integration instructions"
