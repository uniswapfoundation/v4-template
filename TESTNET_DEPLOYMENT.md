# Testnet Deployment with HookMiner - Following Uniswap v4 Guide

This guide follows the official [Uniswap v4 Hook Deployment Guide](https://docs.uniswap.org/contracts/v4/guides/hooks/hook-deployment) for deploying hooks to testnets using CREATE2 with mined addresses.

## 🎯 Hook Address Mining & CREATE2 Deployment

Our implementation follows the official Uniswap v4 pattern:

### Hook Flags Configuration

The PerpsHook requires these specific flags encoded in the address:

```solidity
uint160 flags = uint160(
    Hooks.AFTER_INITIALIZE_FLAG |           // 4096 - Initialize market state
    Hooks.BEFORE_ADD_LIQUIDITY_FLAG |       // 2048 - Block liquidity operations
    Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |    // 512  - Block liquidity operations
    Hooks.BEFORE_SWAP_FLAG |                // 128  - Core perp trading logic
    Hooks.AFTER_SWAP_FLAG |                 // 64   - Execute position operations
    Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG    // 8    - Override swap behavior
);
// Total flags: 6856
```

### CREATE2 Deployment Process

Following the Uniswap v4 guide, our deployment:

1. **Mines the address** using HookMiner to find a salt that produces an address with the correct flags
2. **Deploys using CREATE2** with the mined salt: `new PerpsHook{salt: salt}(...)`
3. **Verifies the deployment** by checking the deployed address matches the mined address

## ETH/USD Pyth Price Feed

The deployment uses the standard ETH/USD Pyth price feed ID across all networks:
```
0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace
```

## Supported Networks

The deployment script automatically configures the correct Pyth contract address based on the `DEPLOYMENT_NETWORK` environment variable:

| Network | Pyth Contract Address | Hook Deployment |
|---------|----------------------|------------------|
| `anvil` | `0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF` | Placeholder (local testing) |
| `sepolia` | `0xDd24F84d36BF92C65F92307595335bdFab5Bbd21` | CREATE2 deployment |
| `arbitrum-sepolia` | `0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF` | CREATE2 deployment |
| `unichain-sepolia` | `0x2880aB155794e7179c9eE2e38200202908C17B43` | CREATE2 deployment |
| `mainnet` | `0x4305FB66699C3B2702D4d05CF36551390A4c69C6` | CREATE2 deployment |
| `arbitrum` | `0xff1a0f4744e8582DF1aE09D5611b887B6a12925C` | CREATE2 deployment |
| `polygon` | `0xff1a0f4744e8582DF1aE09D5611b887B6a12925C` | CREATE2 deployment |
| `base` | `0x8250f4aF4B972684F7b336503E2D6dFeDeB1487a` | CREATE2 deployment |
| `optimism` | `0xff1a0f4744e8582DF1aE09D5611b887B6a12925C` | CREATE2 deployment |

## 🚀 Deployment Commands

### Local Development (Anvil)
```bash
make deploy-production-miner-anvil
```
- Uses placeholder hook address
- Displays CREATE2 parameters for production use
- Perfect for testing core protocol functionality

### Sepolia Testnet
```bash
make deploy-production-miner-sepolia
```
- Deploys hook using CREATE2 with mined salt
- Uses Sepolia Pyth contract
- Includes contract verification

### Arbitrum Sepolia Testnet
```bash
make deploy-production-miner-arbitrum-sepolia
```
- Deploys hook using CREATE2 with mined salt
- Uses Arbitrum Sepolia Pyth contract
- Includes contract verification

### Unichain Sepolia Testnet
```bash
make deploy-production-miner-unichain-sepolia
```
- Deploys hook using CREATE2 with mined salt
- Uses Unichain Sepolia Pyth contract
- Real PoolManager address: `0x00B036B58a818B1BC34d502D3fE730Db729e62AC`

### Mainnet (Production)
```bash
make deploy-production-miner-mainnet
```
- Full production deployment
- Requires user confirmation
- Uses mainnet Pyth contract

## 📋 Environment Setup

Create a `.env` file with the following variables:

```bash
# Private key for deployment
PRIVATE_KEY=your_private_key_here

# RPC URLs
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/your_key
ARBITRUM_SEPOLIA_RPC_URL=https://sepolia-rollup.arbitrum.io/rpc
UNICHAIN_SEPOLIA_RPC_URL=https://sepolia.unichain.org
MAINNET_RPC_URL=https://mainnet.infura.io/v3/your_key

# API Keys for verification
ETHERSCAN_API_KEY=your_etherscan_api_key
ARBISCAN_API_KEY=your_arbiscan_api_key
```

## 🔧 HookMiner Integration Details

### How It Works

Following the Uniswap v4 guide, our implementation:

```solidity
// 1. Define required flags
uint160 flags = uint160(
    Hooks.AFTER_INITIALIZE_FLAG |
    Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
    // ... other flags
);

// 2. Mine a salt that produces the correct address
bytes memory constructorArgs = abi.encode(poolManager, positionManager, ...);
(address hookAddress, bytes32 salt) = HookMiner.find(
    CREATE2_DEPLOYER,
    flags,
    type(PerpsHook).creationCode,
    constructorArgs
);

// 3. Deploy using CREATE2 with the mined salt
PerpsHook perpsHook = new PerpsHook{salt: salt}(
    IPoolManager(poolManager),
    positionManager,
    // ... constructor args
);

// 4. Verify deployment
require(address(perpsHook) == hookAddress, "Hook address mismatch");
```

### CREATE2 Deployer

Uses the standard CREATE2 deployer: `0x4e59b44847b379578588920cA78FbF26c0B4956C`

## 📊 Deployment Process

### Phase 1: Token Infrastructure
- MockUSDC deployment  
- MockVETH deployment
- Initial minting

### Phase 2: Core Protocol Contracts
- MarginAccount (centralized USDC management)
- InsuranceFund (protocol insurance)
- FundingOracle (Pyth integration)

### Phase 3: Hook Mining & Deployment
- **Address Mining**: HookMiner finds valid address with correct flags
- **CREATE2 Deployment**: Hook deployed to exact mined address
- **Verification**: Address validation confirms correct deployment

### Phase 4: Integration Contracts
- PerpsRouter (trading interface)
- PositionManager (position management)

### Phase 5: Liquidation System
- LiquidationEngine deployment

### Phase 6: Authorization & Configuration
- Contract permission setup
- Pyth feed configuration
- Initial funding

## ✅ Deployment Verification

Each deployment includes:

1. **Hook Address Validation**: Confirms deployed address matches mined address
2. **Flag Verification**: Ensures hook has correct permission flags (6856)
3. **Contract Verification**: Etherscan/Arbiscan verification for transparency
4. **Integration Testing**: Authorization and configuration validation

## 🧪 Testing Network Configuration

Test the network configuration:

```bash
# Test default network (anvil)
forge script script/TestNetworkConfig.s.sol:TestNetworkConfigScript

# Test specific network
DEPLOYMENT_NETWORK=sepolia forge script script/TestNetworkConfig.s.sol:TestNetworkConfigScript
```

## 📝 Production Deployment Notes

### For Real Uniswap v4 Deployment:

1. **Update PoolManager Address**: Replace placeholder with actual deployed PoolManager
2. **Use Mined Salt**: Deploy with exact salt found by HookMiner
3. **Verify Address Match**: Ensure deployed address equals mined address
4. **Validate Flags**: Confirm hook address has flags value `6856`

### Key Deployment Parameters:

- **CREATE2 Deployer**: `0x4e59b44847b379578588920cA78FbF26c0B4956C`
- **Required Flags**: `6856` (binary encoding of hook permissions)
- **ETH/USD Feed**: `0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace`

## 🔗 Additional Resources

- [Uniswap v4 Hook Deployment Guide](https://docs.uniswap.org/contracts/v4/guides/hooks/hook-deployment)
- [HookMiner Documentation](https://github.com/Uniswap/v4-periphery/blob/main/src/utils/HookMiner.sol)
- [CREATE2 Deployer Proxy](https://github.com/Arachnid/deterministic-deployment-proxy)
- [Pyth Network Documentation](https://docs.pyth.network/)

## 🚨 Important Notes

- **Testnet vs Production**: Local anvil uses placeholder addresses, testnets use real CREATE2 deployment
- **Address Validation**: Hook addresses must have exact flag validation for Uniswap v4 compatibility
- **Network-Specific**: Each network has its own Pyth contract address
- **Gas Considerations**: CREATE2 deployment and address mining require additional gas
