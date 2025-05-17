# VCOP Stablecoin with Uniswap v4

A collateralized stablecoin backed by USDC with a Peg Stability Module (PSM) operating through a Uniswap v4 hook.

## Description

VCOP is a collateralized stablecoin that maintains its target peg of 1 COP thanks to a collateral-based Peg Stability Module (PSM) and automatic monitoring via a Uniswap v4 hook. The system integrates:

- `VCOPCollateralized.sol`: Collateralized stablecoin token with 6 decimals
- `VCOPOracle.sol`: Price oracle for VCOP/COP and USD/COP rates
- `VCOPCollateralHook.sol`: Uniswap v4 hook implementing the PSM and monitoring swaps
- `VCOPPriceCalculator.sol`: Auxiliary price calculator for accurate rate conversion

## Deployed Contracts

### Base Mainnet Deployment

All contracts are deployed on Base Mainnet. Click on the addresses to view them on BaseScan:

| Contract | Address | Description |
|----------|---------|-------------|
| [VCOP Token](https://basescan.org/address/0xE126098b5111330ceD47b80928348E4B8ED7A784) | `0xE126098b5111330ceD47b80928348E4B8ED7A784` | Collateralized stablecoin token |
| [VCOP Oracle](https://basescan.org/address/0xA3aCc71fDA8C0E321ea9d49eF0630Dc1c1951E17) | `0xA3aCc71fDA8C0E321ea9d49eF0630Dc1c1951E17` | Price oracle for rates |
| [VCOP Collateral Hook](https://basescan.org/address/0x00feAFe88e9441C10227Be8CcF2DC34D691b84c0) | `0x00feAFe88e9441C10227Be8CcF2DC34D691b84c0` | Uniswap v4 hook implementing PSM |
| [VCOP Collateral Manager](https://basescan.org/address/0x5d211f80A23f04201C6b3Fa06B85171b11802B95) | `0x5d211f80A23f04201C6b3Fa06B85171b11802B95` | Collateral reserves manager |
| [VCOP Price Calculator](https://basescan.org/address/0x5F56a7Eb5CD6aa8fC904d6dFEA676BE7C9Dabd26) | `0x5F56a7Eb5CD6aa8fC904d6dFEA676BE7C9Dabd26` | Price calculation helper |
| [Mock USDC](https://basescan.org/address/0xC9D7A317B5A9B39d971fA4430d0Fec7A572d2520) | `0xC9D7A317B5A9B39d971fA4430d0Fec7A572d2520` | Collateral token (test version) |
| [Uniswap Pool Manager](https://basescan.org/address/0x498581ff718922c3f8e6a244956af099b2652b2b) | `0x498581ff718922c3f8e6a244956af099b2652b2b` | Uniswap v4 pool manager |
| [Uniswap Position Manager](https://basescan.org/address/0x7c5f5a4bbd8fd63184577525326123b519429bdc) | `0x7c5f5a4bbd8fd63184577525326123b519429bdc` | Uniswap v4 position manager |

### Base Sepolia Testnet Deployment

The contracts are also deployed on Base Sepolia for testing purposes:

| Contract | Address | Description |
|----------|---------|-------------|
| [VCOP Token](https://sepolia.basescan.org/address/0x3D384BeB1Ba0197e6a87668E1D68267164c8B776) | `0x3D384BeB1Ba0197e6a87668E1D68267164c8B776` | Collateralized stablecoin token |
| [VCOP Oracle](https://sepolia.basescan.org/address/0x046fFDe3161CD0a8DCBF7e1c433f5f510703d56d) | `0x046fFDe3161CD0a8DCBF7e1c433f5f510703d56d` | Price oracle for rates |
| [VCOP Collateral Hook](https://sepolia.basescan.org/address/0xb1D909689f88Bd34340f477A0Bad3956113944C0) | `0xb1D909689f88Bd34340f477A0Bad3956113944C0` | Uniswap v4 hook implementing PSM |
| [VCOP Collateral Manager](https://sepolia.basescan.org/address/0x8f17E2128a4F917ec4147c15FC90bADd79E7F090) | `0x8f17E2128a4F917ec4147c15FC90bADd79E7F090` | Collateral reserves manager |
| [VCOP Price Calculator](https://sepolia.basescan.org/address/0x12C8498b96714615B7bF98456058D48e01C59DB3) | `0x12C8498b96714615B7bF98456058D48e01C59DB3` | Price calculation helper |
| [Mock USDC](https://sepolia.basescan.org/address/0x5405e3a584014c8659BA10591c1b7D55cB1cFc0d) | `0x5405e3a584014c8659BA10591c1b7D55cB1cFc0d` | Collateral token (test version) |
| [Uniswap Pool Manager](https://sepolia.basescan.org/address/0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408) | `0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408` | Uniswap v4 pool manager |
| [Treasury](https://sepolia.basescan.org/address/0xA6B3D200cD34ca14d7579DAc8B054bf50a62c37c) | `0xA6B3D200cD34ca14d7579DAc8B054bf50a62c37c` | Treasury for system fees |

## System Architecture

```
┌───────────────────────────── UNISWAP V4 INTEGRATION ────────────────────────────┐
│                                                                                 │
│  ┌────────────────────────┐                  ┌───────────────────────────────┐  │
│  │   Uniswap v4 Pool      │                  │     Pool Events & Hooks       │  │
│  │                        │                  │                               │  │
│  │  VCOP/USDC Liquidity   │◄───Monitors──────┤ • beforeSwap                  │  │
│  │  Price Discovery       │                  │ • afterSwap                   │  │
│  │  Swap Execution        │──Hook Callbacks─►│ • afterAddLiquidity           │  │
│  └──────────┬─────────────┘                  └────────────────┬──────────────┘  │
│             │                                                 │                 │
│             │                                                 │                 │
│             │           ┌─────────────────────┐               │                 │
│             └──────────►│  Uniswap Pool State │◄──────────────┘                 │
│                         │                     │                                 │
│                         │ • sqrtPriceX96      │◄───────┐                        │
│                         │ • liquidity         │        │                        │
│                         │ • tick              │        │                        │
│                         └──────────┬──────────┘        │                        │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │                  │
                                      │                  │ Reads Price
                                      │                  │
          ┌─────────────────────┐     │                  │
          │      External       │     │                  │
          │      Systems        │     │                  │
          │  (USDC, Users)      │     │                  │
          └──────────┬──────────┘     │                  │
                     │                │                  │
                     │                │                  │
                     ▼                ▼                  ▼
┌─────────────────────────────┐     ┌─────────────────────────────┐
│    VCOPCollateralHook       │     │       VCOPOracle            │
├─────────────────────────────┤     ├─────────────────────────────┤
│ HOOK IMPLEMENTATION:        │     │ PRICE DATA:                 │
│ - getHookPermissions()      │     │ - getVcopToCopRate()        │
│ - _beforeSwap()             │     │ - getUsdToCopRate()         │
│ - _afterSwap()              │     │ - updateRatesFromPool()     │
├─────────────────────────────┤     └────────────┬────────────────┘
│ PSM OPERATIONS:             │                  │
│ - psmSwapVCOPForCollateral()│                  │
│ - psmSwapCollateralForVCOP()│                  │
│ - stabilizePriceWithPSM()   │                  │
├─────────────────────────────┤                  │
│ STABILITY CONTROL:          │                  │
│ - monitorPrice()            │                  │
│ - _wouldBreakPeg()          │                  │
│ - _isLargeSwap()            │                  │
└───────┬─────────┬───────────┘                  │
        │         │                              │
        │         │                  ┌─────────────────────────────┐
        │         │                  │    VCOPPriceCalculator      │
        │         │                  ├─────────────────────────────┤
        │         │                  │ POOL PRICE CALCULATION:     │
        │         │                  │ - getVcopToUsdPriceFromPool()│
        │         │                  │ - getVcopToCopPrice()       │
        │         │                  │ - createPoolKey()           │
        │         │                  │ - isVcopAtParity()          │
        │         │                  └─────────────────────────────┘
        │         │
        │         ▼
        │  ┌─────────────────────────────┐
        │  │     VCOPCollateralManager   │
        │  ├─────────────────────────────┤
        │  │ RESERVES MANAGEMENT:        │
        │  │ - mintPSMVcop()             │
        │  │ - transferPSMCollateral()   │
        │  │ - registerPSMFunds()        │
        │  │ - hasPSMReservesFor()       │
        │  │ - getPSMReserves()          │
        │  └────────────────┬────────────┘
        │                   │
        │                   │
        ▼                   ▼
┌─────────────────────────────┐
│    VCOPCollateralized       │
├─────────────────────────────┤
│ TOKEN OPERATIONS:           │
│ - mint()                    │
│ - burn()                    │
│ - transfer()/transferFrom() │
└─────────────────────────────┘
```

## Uniswap v4 Integration Details

### 1. Hook Implementation

The `VCOPCollateralHook` contract integrates with Uniswap v4 through the hook interface:

```solidity
function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
    return Hooks.Permissions({
        beforeInitialize: false,
        afterInitialize: false,
        beforeAddLiquidity: false,
        afterAddLiquidity: true,
        beforeRemoveLiquidity: false,
        afterRemoveLiquidity: false,
        beforeSwap: true,
        afterSwap: true,
        beforeDonate: false,
        afterDonate: false,
        beforeSwapReturnDelta: false,
        afterSwapReturnDelta: false,
        afterAddLiquidityReturnDelta: false,
        afterRemoveLiquidityReturnDelta: false
    });
}
```

This hook implementation allows the contract to:
1. **Monitor swaps** - Be notified before and after swaps occur in the VCOP/USDC pool
2. **Track liquidity** - Be notified after liquidity is added to the pool
3. **Take action** - Execute stabilization operations when necessary

### 2. Price Monitoring & Stabilization

When a swap occurs in the VCOP/USDC pool:

1. The **beforeSwap** hook is triggered:
   - Checks if the swap is large enough to potentially break the peg
   - Can preemptively execute stabilization if needed

2. The **afterSwap** hook is triggered:
   - Monitors the price after the swap is completed
   - Triggers the PSM stabilization mechanism if the price is outside bounds

3. **Price evaluation process**:
   ```
   Uniswap Pool → VCOPOracle → VCOPPriceCalculator → VCOPCollateralHook
   ```
   - PriceCalculator reads the pool's `sqrtPriceX96` value
   - Converts to VCOP/USDC and then to VCOP/COP
   - Returns this to the hook for evaluation

4. **Stabilization triggers** when price crosses thresholds:
   - If VCOP < pegLowerBound: Buy VCOP with collateral (raise price)
   - If VCOP > pegUpperBound: Sell VCOP for collateral (lower price)

### 3. PSM Direct Operations

Users can directly interact with the PSM through two main functions:

1. **psmSwapVCOPForCollateral**:
   ```
   User → [VCOP tokens] → VCOPCollateralHook → Burns VCOP → VCOPCollateralManager → [USDC] → User
   ```

2. **psmSwapCollateralForVCOP**:
   ```
   User → [USDC] → VCOPCollateralHook → VCOPCollateralManager → Mints VCOP → [VCOP tokens] → User
   ```

## Contract Interactions

### 1. Core Process Flows

#### PSM Swap Flow (User → VCOP)
1. User initiates PSM swap via `VCOPCollateralHook` functions
2. Hook transfers collateral to/from `VCOPCollateralManager`  
3. Manager instructs token contract to mint/burn VCOP
4. User receives VCOP tokens or collateral tokens

#### Price Monitoring Flow
1. Uniswap V4 swap triggers hook callbacks in `VCOPCollateralHook`
2. Hook calls `VCOPOracle` to check current prices
3. Oracle uses `VCOPPriceCalculator` to get accurate pool prices
4. Hook executes stability operations if price is outside target range

#### Automatic Stabilization Flow
1. Large swap is detected in the pool through beforeSwap hook
2. System evaluates if swap would break peg using `_wouldBreakPeg()`
3. If necessary, initiates `stabilizePriceWithPSM()` operation
4. Based on price deviation, executes buy or sell operation via PSM

### 2. Key Contract Responsibilities

#### VCOPCollateralHook
- **Primary Role**: Uniswap v4 hook for monitoring pool activity and price
- **Key Functions**:
  - `psmSwapVCOPForCollateral()`: User-facing function to sell VCOP for collateral
  - `psmSwapCollateralForVCOP()`: User-facing function to buy VCOP with collateral
  - `stabilizePriceWithPSM()`: Automated market operations to maintain peg
  - `monitorPrice()`: Check if VCOP price is within target bounds
  - `_beforeSwap()/_afterSwap()`: Hook callbacks from Uniswap v4

#### VCOPCollateralManager
- **Primary Role**: Manage collateral reserves and token minting permissions
- **Key Functions**:
  - `mintPSMVcop()`: Create new VCOP tokens backed by collateral
  - `transferPSMCollateral()`: Move collateral tokens from reserves
  - `registerPSMFunds()`: Record new collateral in the system
  - `hasPSMReservesFor()`: Check if sufficient reserves exist for an operation
  - `getPSMReserves()`: Get current collateral and VCOP reserve amounts

#### VCOPCollateralized
- **Primary Role**: ERC-20 stablecoin token implementation
- **Key Functions**:
  - `mint()`: Create new tokens (restricted to authorized callers)
  - `burn()`: Destroy tokens (restricted to authorized callers)
  - `transfer()` & `transferFrom()`: Standard ERC-20 token operations

#### VCOPOracle
- **Primary Role**: Provide exchange rates for the system
- **Key Functions**:
  - `getVcopToCopRate()`: Get current VCOP/COP exchange rate
  - `getUsdToCopRate()`: Get current USD/COP exchange rate
  - `updateRatesFromPool()`: Update rates from Uniswap pool data

#### VCOPPriceCalculator
- **Primary Role**: Handle complex price calculations from Uniswap pool data
- **Key Functions**:
  - `getVcopToUsdPriceFromPool()`: Calculate VCOP/USD price from pool's sqrtPriceX96
  - `getVcopToCopPrice()`: Convert to VCOP/COP rate
  - `isVcopAtParity()`: Check if VCOP is at target 1:1 parity with COP
  - `createPoolKey()`: Generate the PoolKey needed to query Uniswap v4

## Requirements

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js and npm
- ETH on Base Sepolia for gas fees
- USDC on Base Sepolia for collateral

## Installation

```bash
# Clone the repository
git clone https://github.com/your-username/VCOPstablecoinUniswapv4.git
cd VCOPstablecoinUniswapv4

# Install dependencies
forge install
```

## Key Commands

### Mainnet Operations

```bash
# Check PSM status and reserves on mainnet
make check-psm-mainnet

# Check current prices from the oracle on mainnet
make check-prices-mainnet

# Swap VCOP for USDC on mainnet (default 100 VCOP)
make swap-vcop-to-usdc-mainnet [AMOUNT=X]

# Swap USDC for VCOP on mainnet (default 100 USDC)
make swap-usdc-to-vcop-mainnet [AMOUNT=X]

# Check rates from oracle on mainnet
make check-new-oracle-mainnet

# Run interactive mainnet command script
./script/MainnetCommands.sh
```

### PSM Operations (Testnet)

```bash
# Check PSM status and reserves
make check-psm

# Check current prices from the oracle
make check-prices

# Swap VCOP for USDC (default 100 VCOP)
make swap-vcop-to-usdc [AMOUNT=X]

# Swap USDC for VCOP (default 100 USDC)
make swap-usdc-to-vcop [AMOUNT=X]
```

### System Management

```bash
# Update oracle to fix conversion rate
make update-oracle

# Deploy entire system with fixed parity
make deploy-fixed-system

# Clean pending transactions
make clean-txs

# Test a swap with the newly deployed system
make test-new-system
```

### Loan System

```bash
# Test full loan cycle (create, add collateral, withdraw, repay)
make test-loans

# Test loan liquidation mechanism
make test-liquidation

# Test PSM functionality
make test-psm

# Create position with specific collateral amount (default 1000 USDC)
make create-position [COLLATERAL=X]
```

## Deployment Flow

### Testnet Deployment

You can deploy the system on Base Sepolia with:

```bash
forge script script/DeployFullSystemFixedParidad.s.sol:DeployFullSystemFixedParidad --rpc-url https://sepolia.base.org --broadcast --gas-price 3000000000 -vv
```

### Mainnet Deployment

The system is already deployed on Base mainnet. If you need to deploy a new instance, you can use:

```bash
# Deploy the system to Base mainnet
make deploy-mainnet

# Or use the deployment script directly
./script/DeployMainnet.sh
```

After deployment, you can verify contracts using:

```bash
./verify-contracts.sh
```

The deployed contracts are documented in `docs/MAINNET_DEPLOYMENT_RECORD.md`.

## Security

This code is experimental and has not been audited. Use at your own risk. 