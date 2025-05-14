# VCOP Collateralized Stablecoin

Collateral-backed stablecoin system pegged to the Colombian peso (COP), built on Uniswap v4.

## System Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────────┐
│ VCOPCollateral  │◄───┤ VCOPCollateral  │◄───┤ VCOPCollateralHook  │
│ (ERC20 Token)   │    │ Manager         │    │ (Uniswap v4 Hook)   │
└────────┬────────┘    └────────┬────────┘    └──────────┬──────────┘
         │                      │                        │
         │                      │                        │
         │                      │                        │
┌────────▼────────┐    ┌────────▼────────┐    ┌──────────▼──────────┐
│ Mock Tokens     │    │ VCOPOracle      │    │ Uniswap v4          │
│ (USDC, etc)     │    │                 │    │ Pool                │
└─────────────────┘    └────────┬────────┘    └─────────────────────┘
                                │
                       ┌────────▼────────┐
                       │ VCOPPrice       │
                       │ Calculator      │
                       └─────────────────┘
```

## Main Components

### VCOPCollateralized.sol
- ERC20 token with 6 decimals (compatible with USDC)
- Special permissions for minting/burning controlled by the manager
- Stability mechanism based on collateralization instead of rebases

### VCOPCollateralManager.sol
- Manages collateral positions for users
- Allows creating/modifying/closing positions
- Handles liquidations of under-collateralized positions
- Implements the Peg Stability Module (PSM)

### VCOPCollateralHook.sol
- Uniswap v4 hook that monitors prices
- Activates stability mechanisms when the price deviates
- Integrates with the collateral system for automatic interventions
- Allows direct exchange operations through the PSM

### VCOPOracle.sol
- Provides VCOP/COP and USD/COP exchange rates
- Uses the Uniswap v4 pool as the primary price source
- Common interface for the entire system

### VCOPPriceCalculator.sol
- Calculates exact prices from Uniswap v4 data
- Determines if VCOP is at parity with COP
- Provides auxiliary functions for the system

## Deployment Workflow

### STEP 1: Deploy Simulated USDC
- Deploy MockERC20 as USDC for testing environment
- Mint initial amount for the deployer

### STEP 2: Deploy VCOPCollateralized Token
- Implement the ERC20 token with 6 decimals
- Configure initial permissions (owner as minter/burner)

### STEP 3: Deploy Oracle and Price Calculator
- Deploy VCOPOracle with initial USD/COP rate (4200)
- Deploy VCOPPriceCalculator
- Configure the calculator in the oracle

### STEP 4: Deploy Hook with HookMiner
- Calculate address with correct flags (BEFORE_SWAP, AFTER_SWAP, AFTER_ADD_LIQUIDITY)
- Deploy hook at the calculated address
- Initialize with references to poolManager and oracle

### STEP 5: Deploy VCOPCollateralManager
- Implement the collateral manager
- Connect it with the VCOP token and oracle
- Configure hook with reference to the manager
- Configure token with reference to the manager

### STEP 6: Configure Collaterals and Permissions
- Register USDC as accepted collateral
- Set collateralization ratios (150%)
- Configure liquidation thresholds (120%)
- Assign mint/burn permissions to the manager

### STEP 7: Create Pool and Add Trading Liquidity
- Create PoolKey for the VCOP/USDC pair with the hook
- Calculate initial price (1 VCOP = 1/4200 USDC)
- Initialize pool with calculated price
- Add initial liquidity for trading

### STEP 8: Provision Liquidity to the Collateral System
- Transfer USDC to the collateral system
- Mint initial VCOP for the PSM
- Configure PSM parameters (fees, limits)
- Initialize stability funds

## Configuration Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| **Initial USD/COP Rate** | 4200 * 10^6 | 4200 COP = 1 USD |
| **Collateralization Ratio** | 150% | For each 1 VCOP, collateral valued at 1.5 COP is required |
| **Liquidation Threshold** | 120% | Below this ratio, positions can be liquidated |
| **PSM Fee** | 0.1% | Fee for using the stability module |
| **Pool Fee** | 0.3% | Uniswap v4 fee for swaps |
| **Parity Bands** | ±1% | Allowed price fluctuation range |

## Initial Liquidity

| Component | USDC | VCOP | Ratio |
|------------|------|------|-------|
| **Trading Pool** | 100,000 | 420,000,000 | 1:4200 |
| **Collateral System (PSM)** | 100,000 | 420,000,000 | 1:4200 |
| **Emergency Reserve** | 10,000 | - | - |

## System Usage

### Create Collateralized Position
```solidity
// Approve collateral transfer
IERC20(usdcAddress).approve(address(collateralManager), 1000e6);

// Create position with 1000 USDC as collateral
collateralManager.createPosition(usdcAddress, 1000e6, 600e6); // Get 600 VCOP
```

### Repay Debt and Recover Collateral
```solidity
// Approve VCOP transfer for repayment
IERC20(vcopAddress).approve(address(collateralManager), 600e6);

// Repay debt
collateralManager.repayDebt(positionId, 600e6);
```

### Exchange via PSM
```solidity
// Exchange VCOP for USDC using PSM
IERC20(vcopAddress).approve(address(hook), 100e6);
hook.psmSwapVCOPForCollateral(100e6);

// Exchange USDC for VCOP using PSM
IERC20(usdcAddress).approve(address(hook), 0.02381e6); // 0.02381 USDC ≈ 100 VCOP
hook.psmSwapCollateralForVCOP(0.02381e6);
```

## Advantages over Rebase System

1. **Greater transparency**: Users have full visibility of their collateral backing
2. **Risk control**: Configurable collateralization ratios for different assets
3. **Scalability**: Support for multiple collateral types
4. **Resistance to volatility**: Cushioning of sharp changes through the PSM
5. **DeFi integration**: Compatible with standard DeFi applications without rebase issues

## Deployment Commands

```shell
# Prepare environment variables
export PRIVATE_KEY=0x...
export POOL_MANAGER_ADDRESS=0x...
export POSITION_MANAGER_ADDRESS=0x...

# Run deployment script
forge script script/DeployVCOPCollateral.sol:DeployVCOPCollateral \
  --via-ir \
  --broadcast \
  --fork-url https://sepolia.base.org
``` 