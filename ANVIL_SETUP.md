# Anvil Local Development Setup

This guide walks you through setting up a local Uniswap v4 development environment using Anvil for testing our PerpsHook implementation.

## Quick Start

### 1. Start Anvil Local Blockchain

In one terminal, start the Anvil local blockchain:

```bash
make start-anvil
```

This will start Anvil with the default configuration, exposing the RPC at `http://localhost:8545`.

### 2. Deploy Uniswap v4 Contracts

In another terminal, deploy all the necessary Uniswap v4 contracts and our PerpsHook:

```bash
make deploy-anvil
```

This command deploys:
- **PoolManager**: The core Uniswap v4 pool manager
- **Test Routers**: 
  - PoolSwapTest
  - PoolModifyLiquidityTest  
  - PoolDonateTest
  - PoolTakeTest
  - PoolClaimsTest
- **Mock Tokens**: MockUSDC and MockVETH with test balances
- **PositionManager**: Our NFT-based position management system
- **PerpsHook**: Our perpetual futures trading hook

### 3. Run Tests Against Anvil

Run tests against the deployed contracts on Anvil:

```bash
make test-anvil
```

## Deployed Contract Addresses

After running `make deploy-anvil`, you'll see output like:

```
=== Deployment Summary ===
PoolManager: 0x5fbdb2315678afecb367f032d93f642f64180aa3
SwapRouter: 0xe7f1725e7734ce288f8367e1bb143e90bb3f0512
ModifyLiquidityRouter: 0x9fe46736679d2d9a65f0992f2272de9f3c7fa6e0
DonateRouter: 0xcf7ed3acca5a467e9e704c703e8d87f634fb0fc9
TakeRouter: 0xdc64a140aa3e981100a9beca4e685f962f0cf6c9
ClaimsRouter: 0x5fc8d32690cc91d4c39d9d3abcbd16989f875707
USDC Token: 0x0165878a594ca255338adfa4d48449f69242eb8f
ETH Token: 0xa513e6e4b8f2a923d98304ec87f64353c4d5c853
PositionManager: 0x2279b7a0a67db372996a5fab50d91eaa73d2ebe6
PerpsHook: 0x8a791620dd6260079bf849dc5567adc3f2fdc318

Test Accounts:
Deployer: 0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266
User1: 0x70997970c51812dc3a010c7d01b50e0d17dc79c8
User2: 0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc
```

## Test Account Balances

The deployment script automatically mints tokens to test accounts:

**Deployer (0xf39fd...):**
- 1,000,000 USDC (1M USDC)
- 1,000 ETH

**User1 (0x70997...):**
- 100,000 USDC
- 100 ETH

**User2 (0x3c44c...):**
- 100,000 USDC  
- 100 ETH

**PerpsHook Contract:**
- 100,000 USDC (for PnL payouts)

## Available Commands

```bash
# Start local blockchain
make start-anvil

# Deploy contracts to Anvil
make deploy-anvil

# Run tests against Anvil
make test-anvil

# Standard testing (against Foundry test environment)
make test-position-manager
make test-perps-hook
```

## Using the Deployed Contracts

### Example: Interacting with PerpsHook

Once deployed, you can interact with the contracts using cast or custom scripts:

```bash
# Check PerpsHook owner
cast call <PERPS_HOOK_ADDRESS> "owner()" --rpc-url http://localhost:8545

# Check USDC balance of User1
cast call <USDC_ADDRESS> "balanceOf(address)" 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 --rpc-url http://localhost:8545

# Check PositionManager contract
cast call <POSITION_MANAGER_ADDRESS> "collateralToken()" --rpc-url http://localhost:8545
```

### Creating a Pool and Testing Trades

The next step would be to:

1. Create a pool using the PoolManager
2. Initialize the pool with our PerpsHook
3. Set up markets in the PositionManager
4. Execute test trades through the hook

## Environment Configuration

The Anvil deployment uses:
- **Deployer Private Key**: `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` (Anvil default)
- **RPC URL**: `http://localhost:8545`
- **Chain ID**: 31337 (Anvil default)

## Next Steps

With this setup, you can:

1. **Test Hook Functionality**: Use the deployed contracts to test position opening/closing
2. **Develop Frontend**: Connect a web3 frontend to the local contracts
3. **Test Integrations**: Test how the PerpsHook interacts with other protocols
4. **Debug and Iterate**: Use Anvil's state forking and debugging features

## Troubleshooting

**Build Issues**: Make sure all dependencies are installed with `forge install`

**Deployment Fails**: Ensure Anvil is running and accessible at `http://localhost:8545`

**Test Failures**: The PerpsHook tests may fail due to Uniswap v4 hook address validation requirements. This is expected for basic testing and would be resolved in production with proper hook address deployment.

**Gas Issues**: Anvil provides unlimited gas by default, so this shouldn't be an issue during development.
