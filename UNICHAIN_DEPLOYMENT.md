# Unichain Sepolia Deployment Guide

## Overview
This guide walks through deploying the modular Perpetual Futures Protocol to Unichain Sepolia testnet using the `DeployProductionWithMiner.s.sol` script.

## Prerequisites

### 1. Environment Setup
You need to set the following environment variables:

```bash
## Deployment Process

### Step 1: Set Environment Variables
```bash
# Set your private key (replace with your actual private key)
export PRIVATE_KEY="your_private_key_here"

# Set deployment network
export DEPLOYMENT_NETWORK="unichain-sepolia"
```

### Step 2: Verify Balance
Check that your deployer address has sufficient ETH:
```bash
# Get your deployer address
cast wallet address --private-key $PRIVATE_KEY

# Check balance on Unichain Sepolia
cast balance $(cast wallet address --private-key $PRIVATE_KEY) --rpc-url https://sepolia.unichain.org
```

### Step 3: Test Deployment (Optional)
Test the deployment without broadcasting to see what will happen:
```bash
DEPLOYMENT_NETWORK=unichain-sepolia forge script script/DeployProductionWithMiner.s.sol 
  --rpc-url https://sepolia.unichain.org 
  -vvv
```

### Step 4: Run Actual Deployment
Execute the deployment script:
```bash
forge script script/DeployProductionWithMiner.s.sol 
  --rpc-url https://sepolia.unichain.org 
  --broadcast 
  --verify 
  -vvv
```

### Step 5: Save Deployment Addresses
The script will output a comprehensive deployment report including all contract addresses. Save these for later use.
```

### 2. Testnet ETH
Make sure your deployer address has sufficient Unichain Sepolia ETH for gas fees. You can get testnet ETH from:
- Unichain Sepolia Faucet: https://faucet.unichain.org/

### 3. Verify Network Configuration
The script already includes the correct configuration for Unichain Sepolia:
- **Pyth Contract**: `0x2880aB155794e7179c9eE2e38200202908C17B43`
- **PoolManager**: `0x00B036B58a818B1BC34d502D3fE730Db729e62AC`
- **ETH/USD Feed ID**: `0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace`

## Environment Setup

### Option 1: Using Environment Variables

Set the following environment variables in your terminal:

```bash
# Required - Your private key (without 0x prefix for forge)
export PRIVATE_KEY="your_private_key_here"

# Required - Deployment network identifier
export DEPLOYMENT_NETWORK="unichain-sepolia"

# Optional - For contract verification
export ETHERSCAN_API_KEY="your_etherscan_api_key"
```

### Option 2: Using .env File

Create a `.env` file in the project root:

```bash
# .env file
PRIVATE_KEY=your_private_key_here
DEPLOYMENT_NETWORK=unichain-sepolia
ETHERSCAN_API_KEY=your_etherscan_api_key
```

## Network Configuration

The deployment script already includes Unichain Sepolia configuration:

- **Pyth Oracle**: `0x2880aB155794e7179c9eE2e38200202908C17B43`
- **Pool Manager**: `0x00B036B58a818B1BC34d502D3fE730Db729e62AC`
- **RPC URL**: You'll need to get this from Unichain documentation

## Summary

The `DeployProductionWithMiner.s.sol` script is ready to deploy the complete modular Perpetual Futures Protocol to Unichain Sepolia. Here's what you need to do:

### ✅ Script Status
- **Modular Architecture**: ✅ Fully supported (PositionFactory, PositionNFT, MarketManager, PositionManager)
- **Hook Mining**: ✅ Working (mines valid hook address with correct flags 6856)
- **Unichain Sepolia Config**: ✅ Pre-configured (Pyth + PoolManager addresses)
- **Network Detection**: ✅ Properly handles testnet vs local

### 🚀 Quick Deployment Steps

1. **Set environment variables:**
```bash
export PRIVATE_KEY="your_64_char_private_key_without_0x"
export DEPLOYMENT_NETWORK="unichain-sepolia"
```

2. **Verify balance:**
```bash
cast balance $(cast wallet address --private-key $PRIVATE_KEY) --rpc-url https://sepolia.unichain.org
```

3. **Deploy:**
```bash
forge script script/DeployProductionWithMiner.s.sol \
  --rpc-url https://sepolia.unichain.org \
  --broadcast \
  --verify \
  -vvv
```

### 📋 What Gets Deployed
- **Complete System**: All 11 contracts including modular position management
- **Mined Hook**: Actual PerpsHook deployed to Uniswap v4 compatible address
- **Full Authorization**: All contracts properly authorized to interact
- **Initial Funding**: Insurance fund funded with 50,000 USDC
- **Comprehensive Logging**: Complete deployment report with all addresses

The script is production-ready and will deploy the complete system to Unichain Sepolia!
```bash
forge script script/DeployProductionWithMiner.s.sol \
    --rpc-url https://sepolia-unichain.example.com \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY
```

### Deploy Modular Position System Only
```bash
forge script script/DeployModularPositionSystem.s.sol \
    --rpc-url https://sepolia-unichain.example.com \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY
```

## Post-Deployment

After successful deployment:

1. **Save Addresses**: The deployment will output all contract addresses
2. **Verify Contracts**: Contracts should auto-verify if etherscan API key is provided
3. **Test Integration**: Use the examples/ directory to test the deployed contracts
4. **Update Frontend**: Update your frontend with the new contract addresses

## Troubleshooting

### Common Issues:

1. **Insufficient Funds**: Ensure you have enough ETH for gas fees
2. **RPC Issues**: Make sure the RPC URL is correct and responding
3. **Private Key Format**: Remove 0x prefix for forge script commands
4. **Network Mismatch**: Ensure DEPLOYMENT_NETWORK matches the actual network

### Gas Estimation:
- Expected gas usage: ~19M gas units
- At 2 gwei: ~0.038 ETH required

## Contract Sizes (All under EIP-170 limit):
- PositionFactory: 18,128 bytes
- PositionNFT: 10,851 bytes  
- MarketManager: 5,429 bytes
- PositionManager: 11,839 bytes

## Verification

The deployment script includes verification logic to ensure:
- All contracts deployed successfully
- Component relationships configured correctly
- Market setup completed
- Contract sizes under EIP-170 limit
- Authorization permissions set properly
