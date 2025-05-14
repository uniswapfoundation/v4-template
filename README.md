# VCOP Stablecoin with Uniswap v4

A collateralized stablecoin backed by USDC (or other ERC-20 tokens) with a Peg Stability Module (PSM) operating through a Uniswap v4 hook.

## Description

VCOP is a collateralized stablecoin that maintains its target peg of 1 COP thanks to a collateral-based Peg Stability Module (PSM) and automatic monitoring via a Uniswap v4 hook. The system integrates:

- VCOP collateralized token with 6 decimals (`VCOPCollateralized.sol`)
- Price oracle for VCOP/COP and USD/COP rates (`VCOPOracle.sol`)
- Collateral manager and PSM module (`VCOPCollateralManager.sol`)
- Uniswap v4 hook that implements the PSM and monitors large swaps (`VCOPCollateralHook.sol`)
- VCOP/USDC pool on Uniswap v4
- Auxiliary price calculator for the oracle (`VCOPPriceCalculator.sol`)

## Requirements

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js and npm
- ETH on Base Sepolia for gas fees
- USDC on Base Sepolia to add liquidity

## Installation

```bash
# Clone the repository
git clone <repositorio>
cd VCOPstablecoinUniswapv4

# Install dependencies
forge install
```

## Deployment Flow

Deployment can be done in a local environment or on the Base Sepolia network.

### Option 1: Deployment on Base Sepolia

#### 1. Setting up the .env file

The `.env` file is already configured with the official Uniswap v4 contract addresses on Base Sepolia. You only need to update your private key:

```
# Replace with your actual private key (must include 0x prefix)
PRIVATE_KEY=0xtu_clave_privada_aqui

# Base Sepolia RPC URL
RPC_URL=https://sepolia.base.org

# Official Uniswap v4 addresses on Base Sepolia (ChainID: 84532)
POOL_MANAGER_ADDRESS=0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408
POSITION_MANAGER_ADDRESS=0x4b2c77d209d3405f41a037ec6c77f7f5b8e2ca80

# USDC on Base Sepolia
USDC_ADDRESS=0x036CbD53842c5426634e7929541eC2318f3dCF7e
```

#### 2. Get USDC on Base Sepolia

Before deploying, make sure you have enough USDC on Base Sepolia to add initial liquidity. The script is configured to use 50 USDC.

#### 3. Deploy the Complete VCOP System

Run the complete deployment script:

```bash
# Use the --via-ir option to resolve potential "stack too deep" errors
forge script script/DeployVCOPComplete.s.sol:DeployVCOPComplete --via-ir --broadcast --rpc-url base-sepolia
```

This script performs the deployment process in three steps:

1. **Step 1**: Deploys the VCOP token and the Oracle
2. **Step 2**: Uses HookMiner to find and deploy the hook with a valid address for Uniswap v4
3. **Step 3**: Creates the VCOP/USDC pool and adds initial liquidity

The deployed contracts and their addresses will be displayed in the script output.

#### 4. Verify Contracts on BaseScan Sepolia

You can automatically verify the deployed contracts using the included script:

```bash
./verify-contracts.sh
```

The script verifies:
- VCOP Token
- VCOP Oracle
- VCOP Collateral Hook

### Option 2: Secure Two-Phase Deployment

If you prefer a more controlled deployment flow, split the operation into two scripts:

1. **Deploy base contracts** (token, oracle and manager):

```bash
forge script script/DeployVCOPBase.sol:DeployVCOPBase --via-ir --broadcast --rpc-url https://sepolia.base.org
```

2. **Configure the complete system** (hook, PSM, pool and liquidity):

```bash
forge script script/ConfigureVCOPSystem.sol:ConfigureVCOPSystem --via-ir --broadcast --rpc-url https://sepolia.base.org
```

This division provides:

- Enhanced security by limiting required permissions in each phase.
- Easier recovery; if something fails in the second part, you don't need to redeploy the base contracts.
- Clearer code with separated responsibilities.

## Main Scripts

| Script | Description |
|--------|-------------|
| `DeployVCOPBase.sol` | Deploys the base contracts (Token, Oracle, Manager) |
| `ConfigureVCOPSystem.sol` | Configures hook, collaterals, pool and liquidity |
| `DeployVCOPCollateralHook.s.sol` | Deploys only the hook (modular deployment) |
| 


Old scripts and examples have been moved to the `script/archive` folder.

## Running Utility Scripts

### Query Pool Price

To get the current VCOP/USDC price directly from the pool on Base Sepolia, run:

```bash
forge script script/TestPoolPrice.s.sol --rpc-url https://sepolia.base.org
```

This script shows detailed information such as:
- Whether VCOP is token0 or token1 in the pool
- The raw price (token1/token0)
- The VCOP/USDC price (dollar equivalent)
- The VCOP/COP price (Colombian peso equivalent)

### Swap VCOP to USDC

To perform a swap from VCOP to USDC on Base Sepolia:

1. Make sure your account has enough VCOP tokens.
2. Run the following command:

```bash
# Load environment variables and run the script
source .env
forge script script/SwapVCOP.s.sol:SwapVCOPScript --rpc-url base-sepolia --private-key $PRIVATE_KEY --broadcast
```

The script is configured to sell 49,000 VCOP for USDC. If you need to change the amount, modify the `SWAP_AMOUNT` constant in the file `script/SwapVCOP.s.sol`.

## Why do we need HookMiner?

In Uniswap v4, hooks must have special addresses that encode the permissions they use. HookMiner finds a "salt" to deploy the contract using CREATE2 to an address that has the correct bits, allowing Uniswap v4 to validate which hooks are enabled.

## Main Contracts

- `VCOPCollateralized.sol`: Collateralized stablecoin token
- `VCOPOracle.sol`: Price oracle for VCOP/COP & USD/COP rates
- `VCOPCollateralManager.sol`: Collateral manager and PSM reserves
- `VCOPCollateralHook.sol`: Uniswap v4 hook implementing the PSM

## Tests

To run the tests:

```bash
forge test -vv
```

## Interacting with the System

Once deployed, you can:

1. Manually adjust the USD/COP rate in the `VCOPOracle` or run `updateRatesFromPool()` to force synchronization.
2. Make large swaps in the VCOP/USDC pool and observe how the hook executes automatic stabilization operations.
3. Use the public functions of `VCOPCollateralManager` to query PSM reserves and stability statistics.

## Security

This code is experimental and has not been audited. It is not recommended for production use.

## Setup

1. Make sure you have Foundry installed:
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. Clone this repository:
```bash
git clone https://github.com/tu-usuario/VCOPstablecoinUniswapv4.git
cd VCOPstablecoinUniswapv4
```

3. Install dependencies:
```bash
forge install
```

4. Configure environment variables in the `.env` file:
```
PRIVATE_KEY=your_private_key
RPC_URL=https://sepolia.base.org
```

### Important Note

- The script assumes VCOP has 6 decimals.
- Make sure the account associated with your private key has enough VCOP tokens to perform the swap.
- The script uses the PoolSwapTest contract from Uniswap V4 on Base Sepolia.

## Contracts Used

- PoolManager: 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408
- Universal Router: 0x492E6456D9528771018DeB9E87ef7750EF184104
- Position Manager: 0x4B2C77d209D3405F41a037Ec6c77F7F5b8e2ca80
- PoolSwapTest: 0x8B5bcC363ddE2614281aD875bad385E0A785D3B9
- VCOP Token: 0x7aa903a5fEe8F484575D5B8c43f5516504D29306
- USDC Token: 0xF1A811E804b01A113fCE804f2b1C98bE25Ff8557
- VCOP Collateral Hook: 0xe63037ccc7ae9D980f2DFA26D2C37a92937DC4c0 