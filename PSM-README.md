# PSM (Peg Stability Module) Swap Scripts

This directory contains scripts for interacting with the VCOP PSM module on Base Sepolia.

## Prerequisites

1. [Foundry](https://book.getfoundry.sh/getting-started/installation) installed
2. `.env` file with your `PRIVATE_KEY` configured

## Contract Addresses

- **USDC (MockERC20)**: `0x8FB0502d06253915db48b7F5D0bf446B17265C73`
- **VCOP Token**: `0x97CBc4fB89a85681b5f2da1c5569b7938ff8bFa3`
- **VCOP Oracle**: `0xe42D0CBE1e3920673a0A3dC625C9fbFa02B58f5B`
- **VCOP Collateral Hook**: `0x07CFb798c049E71F8D140AEE17c1DE2e647Dc4c0`
- **VCOP Collateral Manager**: `0x95958475f8db84a6Af7e0f155652495990cbE4b2`
- **VCOP Price Calculator**: `0x3fE59E0B1DDd127Ec98fBb7cf4fD617D4e8aA993`

## PSM Swap Flow

The PSM (Peg Stability Module) allows users to swap between VCOP and USDC at a rate close to the peg to help maintain stability.

### VCOP to USDC Swap
1. User approves VCOP for the VCOP Collateral Hook
2. User calls `psmSwapVCOPForCollateral` with the VCOP amount
3. Hook burns VCOP and transfers USDC from reserves to user
4. A fee is taken and sent to the treasury

### USDC to VCOP Swap
1. User approves USDC for the VCOP Collateral Hook
2. User calls `psmSwapCollateralForVCOP` with the USDC amount
3. Hook transfers USDC to collateral reserves and mints VCOP to user
4. A fee is taken and sent to the treasury

## Using the Scripts

### Using Make Commands (Recommended)

```bash
# Check PSM status and user balances
make check-psm

# Check current PSM prices and conversion rates
make check-prices

# Swap 100 VCOP for USDC (default amount)
make swap-vcop-to-usdc

# Swap 100 USDC for VCOP (default amount)
make swap-usdc-to-vcop

# Swap custom amount (e.g., 500 tokens = 500000000 with 6 decimals)
make swap-vcop-to-usdc AMOUNT=500000000
make swap-usdc-to-vcop AMOUNT=500000000
```

### Using Forge Directly

```bash
# Check PSM status
forge script script/PsmCheck.s.sol:PsmCheckScript --rpc-url https://sepolia.base.org -vv

# Swap VCOP for USDC (100 VCOP = 100000000 with 6 decimals)
forge script script/CustomPsmSwap.s.sol:CustomPsmSwapScript --sig "swapVcopToUsdc(uint256)" 100000000 --rpc-url https://sepolia.base.org --broadcast -vv

# Swap USDC for VCOP (100 USDC = 100000000 with 6 decimals)
forge script script/CustomPsmSwap.s.sol:CustomPsmSwapScript --sig "swapUsdcToVcop(uint256)" 100000000 --rpc-url https://sepolia.base.org --broadcast -vv
```

## Best Practices

1. **Always check PSM status before swapping** using `make check-psm` to ensure the PSM is not paused and has sufficient reserves
2. **Check prices and conversion rates** using `make check-prices` to understand the current exchange rate
3. **Start with small amounts** to test the swap functionality before using larger amounts

## Troubleshooting

1. **"Insufficient allowance"** - You need to approve the tokens for the Hook contract
2. **"PSM is paused"** - The PSM module has been temporarily disabled
3. **"Insufficient PSM reserves"** - There's not enough collateral in the PSM to fulfill your request
4. **"Amount exceeds PSM limit"** - Your swap amount is larger than the per-transaction limit 