# Production Deployment Guide

This guide walks you through deploying the complete Perpetual Futures Protocol to production using Mock USDC.

## 🚀 Quick Start

### 1. Environment Setup

```bash
# Copy the environment template
cp .env.example .env

# Edit .env with your configuration
vim .env
```

Required environment variables:
- `PRIVATE_KEY`: Your deployment wallet private key (without 0x prefix)
- `DEPLOYMENT_NETWORK`: Target network (anvil/sepolia/mainnet/arbitrum/polygon)

### 2. Deploy to Local Anvil (Recommended for testing)

```bash
# Start local Anvil node
anvil

# Deploy all contracts
forge script script/DeployProduction.s.sol:DeployProductionScript \
  --rpc-url $ANVIL_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify

# Or use the Makefile shortcut
make deploy-production-anvil
```

### 3. Deploy to Testnet (Sepolia)

```bash
# Deploy to Sepolia
forge script script/DeployProduction.s.sol:DeployProductionScript \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY

# Or use the Makefile shortcut
make deploy-production-sepolia
```

### 4. Deploy to Mainnet

```bash
# Deploy to Mainnet (USE WITH CAUTION)
forge script script/DeployProduction.s.sol:DeployProductionScript \
  --rpc-url $MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY

# Or use the Makefile shortcut
make deploy-production-mainnet
```

## 📋 Deployment Process

The deployment script executes in 7 phases:

### Phase 1: Token Infrastructure
- Deploys MockUSDC (6 decimals) 
- Deploys MockVETH (18 decimals)
- Mints initial supply to deployer

### Phase 2: Core Protocol Contracts
- MarginAccount (USDC collateral vault)
- InsuranceFund (protocol insurance)
- FundingOracle (Pyth price feeds)

### Phase 3: Uniswap V4 Integration
- PositionManager (position lifecycle)
- PerpsHook (automated liquidations)
- PerpsRouter (user interface)

### Phase 4: Liquidation System
- LiquidationEngine (liquidation logic)

### Phase 5: Authorizations
- Sets up cross-contract permissions
- Configures access controls

### Phase 6: Initial Configuration
- Adds ETH-USD market
- Funds insurance fund with 50,000 USDC
- Sets market parameters (50x leverage, 5% maintenance margin)

### Phase 7: Deployment Report
- Generates comprehensive deployment summary
- Outputs JSON configuration for frontend integration

## 📊 Contract Addresses

After deployment, you'll receive a complete report with all contract addresses:

```
TOKEN CONTRACTS:
MockUSDC:          0x...
MockVETH:          0x...

CORE CONTRACTS:
MarginAccount:     0x...
InsuranceFund:     0x...
FundingOracle:     0x...

UNISWAP V4 INTEGRATION:
PositionManager:   0x...
PerpsHook:         0x...
PerpsRouter:       0x...

LIQUIDATION SYSTEM:
LiquidationEngine: 0x...
```

## 🔧 Configuration Options

### Market Parameters (ETH-USD)
- **Base Price**: $2,000
- **Max Leverage**: 50x
- **Maintenance Margin**: 5%
- **Liquidation Fee**: 10%

### Initial Funding
- **Insurance Fund**: 50,000 USDC
- **Deployer Balance**: 1,000,000 USDC (for testing)

### Pyth Oracle Integration
- **Anvil**: Placeholder contract
- **Sepolia**: 0xDd24F84d36BF92C65F92307595335bdFab5Bbd21
- **Mainnet**: 0x4305FB66699C3B2702D4d05CF36551390A4c69C6
- **Arbitrum**: 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C
- **Polygon**: 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C

## 🧪 Post-Deployment Testing

### Verify Deployment
```bash
# Run deployment verification
forge script script/DeployProduction.s.sol:DeployProductionScript \
  --sig "verifyDeployment()" \
  --rpc-url $RPC_URL
```

### Test Basic Functionality
```bash
# Run integration tests
forge test --match-contract "Integration" -vvv

# Test liquidation engine
forge test --match-contract "LiquidationEngine" -vvv

# Test perps router
forge test --match-contract "PerpsRouter" -vvv
```

### Check Balances
```bash
# Check insurance fund balance
cast call $INSURANCE_FUND_ADDRESS "getBalance()" --rpc-url $RPC_URL

# Check deployer USDC balance
cast call $MOCK_USDC_ADDRESS "balanceOf(address)" $DEPLOYER_ADDRESS --rpc-url $RPC_URL
```

## 🔒 Security Considerations

### Production Checklist
- [ ] Use a secure, hardware-backed private key
- [ ] Deploy to testnet first and test thoroughly
- [ ] Verify all contract source code on Etherscan
- [ ] Test all critical functions (deposit, withdraw, liquidation)
- [ ] Confirm oracle price feeds are working
- [ ] Check that insurance fund is properly funded
- [ ] Verify cross-contract authorizations are correct
- [ ] Test emergency functions and pausing mechanisms
- [ ] Confirm time locks and upgrade mechanisms (if any)

### Mock USDC vs Real USDC
- **Mock USDC**: Controlled by deployer, unlimited minting capability
- **Real USDC**: Would require integrating with actual USDC contract
- **For Production**: Replace MockUSDC with real USDC contract address

### Access Controls
- **MarginAccount**: Authorized contracts can transfer funds
- **InsuranceFund**: Authorized contracts can collect fees
- **FundingOracle**: Authorized contracts can update prices
- **Owner Controls**: Add/remove authorized contracts, emergency functions

## 🚨 Troubleshooting

### Common Issues

**"Pyth contract not configured"**
- Ensure DEPLOYMENT_NETWORK is set correctly in .env
- Check that Pyth address is configured for your network

**"Insufficient funds"**
- Ensure deployer wallet has enough ETH for gas
- Check that PRIVATE_KEY is correct and wallet is funded

**"Nonce too low"**
- Wait for previous transactions to confirm
- Use `--slow` flag if needed

**"Contract verification failed"**
- Ensure Etherscan API key is correct
- Wait a few minutes and try verification again manually

### Manual Contract Verification

If automatic verification fails:

```bash
# Verify individual contracts
forge verify-contract $CONTRACT_ADDRESS src/MarginAccount.sol:MarginAccount \
  --chain-id $CHAIN_ID \
  --num-of-optimizations 200 \
  --constructor-args $(cast abi-encode "constructor(address)" $USDC_ADDRESS) \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

## 📈 Next Steps

After successful deployment:

1. **Frontend Integration**: Use the deployment JSON to configure your frontend
2. **Market Making**: Set up initial liquidity in Uniswap V4 pools
3. **Monitoring**: Set up monitoring for liquidations and oracle updates
4. **User Testing**: Conduct thorough user acceptance testing
5. **Mainnet Migration**: When ready, deploy to mainnet with real USDC

## 🔗 Useful Links

- [Foundry Documentation](https://book.getfoundry.sh/)
- [Uniswap V4 Documentation](https://docs.uniswap.org/contracts/v4/overview)
- [Pyth Network Documentation](https://docs.pyth.network/)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)

## 📞 Support

If you encounter issues:
1. Check the troubleshooting section above
2. Review deployment logs for specific error messages
3. Test on Anvil first before deploying to testnets/mainnet
4. Ensure all dependencies are properly installed and updated
