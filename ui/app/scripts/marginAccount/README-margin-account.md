# Margin Account Implementation

A comprehensive TypeScript implementation for interacting with the Margin Account contract on Unichain Sepolia testnet. This implementation provides deposit, withdraw, and balance tracking functionality for the perpetual futures trading system.

## 📁 Files Structure

```
scripts/
├── margin-account.ts    # Main command-line script
├── contracts.ts         # Contract configuration and ABIs
lib/
├── margin-account.ts    # Reusable TypeScript class
app/abi/marginAccount/
├── abi.json            # Margin Account ABI
└── MarginAccount.sol   # Solidity contract source
```

## 🚀 Quick Start

### 1. Environment Setup

Set up your environment variables:

```bash
# Required environment variables
export PRIVATE_KEY="your_private_key_here"
export UNICHAIN_SEPOLIA_RPC_URL="https://sepolia.unichain.org"
export CHAIN_ID="1301"

# Optional: Additional RPC URLs
export RPC_URL="https://sepolia.unichain.org"
export DEPLOYMENT_NETWORK="unichain-sepolia"
export ANVIL_RPC_URL="http://localhost:8545"
export SEPOLIA_RPC_URL="https://ethereum-sepolia-rpc.publicnode.com"
export MAINNET_RPC_URL="https://ethereum-rpc.publicnode.com"
export ARBITRUM_RPC_URL="https://arbitrum-one-rpc.publicnode.com"
export POLYGON_RPC_URL="https://polygon-bor-rpc.publicnode.com"

# API Keys (optional)
export ETHERSCAN_API_KEY="your_etherscan_api_key"
export ARBISCAN_API_KEY="your_arbiscan_api_key"
export POLYGONSCAN_API_KEY="your_polygonscan_api_key"

# Contract addresses
export UNICHAIN_SEPOLIA_POOL_MANAGER="0x00B036B58a818B1BC34d502D3fE730Db729e62AC"
export UNICHAIN_SEPOLIA_PYTH="0x2880aB155794e7179c9eE2e38200202908C17B43"
```

### 2. Install Dependencies

```bash
# Install required packages
bun install
# or
npm install
```

### 3. Run the Script

```bash
# Basic usage
bun run scripts/margin-account.ts <action> <amount> [userAddress]

# Examples
bun run scripts/margin-account.ts deposit 100
bun run scripts/margin-account.ts withdraw 50
bun run scripts/margin-account.ts depositFor 200 0x1234567890123456789012345678901234567890
bun run scripts/margin-account.ts withdrawFor 25 0x1234567890123456789012345678901234567890
```

## 📋 Available Commands

### Deposit Commands

```bash
# Deposit USDC to your margin account
bun run scripts/margin-account.ts deposit 100

# Deposit USDC for another user (requires authorization)
bun run scripts/margin-account.ts depositFor 100 0x1234567890123456789012345678901234567890
```

### Withdraw Commands

```bash
# Withdraw USDC from your margin account
bun run scripts/margin-account.ts withdraw 50

# Withdraw USDC for another user (requires authorization)
bun run scripts/margin-account.ts withdrawFor 25 0x1234567890123456789012345678901234567890
```

## 🔍 Balance Verification Commands

### Direct Contract Calls

```bash
# Check margin account total balance
cast call 0x4Aa68070609C7EE42CDd7E431F202c0577c8556E "getTotalBalance(address)" 0xcFE743EA353d4d3D2c20C41C7d878B2cbA66DA0a --rpc-url https://sepolia.unichain.org

# Check margin account free balance
cast call 0x4Aa68070609C7EE42CDd7E431F202c0577c8556E "freeBalance(address)" 0xcFE743EA353d4d3D2c20C41C7d878B2cbA66DA0a --rpc-url https://sepolia.unichain.org

# Check margin account locked balance
cast call 0x4Aa68070609C7EE42CDd7E431F202c0577c8556E "lockedBalance(address)" 0xcFE743EA353d4d3D2c20C41C7d878B2cbA66DA0a --rpc-url https://sepolia.unichain.org

# Check USDC wallet balance
cast call 0xb2feD1a40Fe6CA0be97Cde27e1D2dF1CC65Fd101 "balanceOf(address)" 0xcFE743EA353d4d3D2c20C41C7d878B2cbA66DA0a --rpc-url https://sepolia.unichain.org
```

### Convert Hex to Decimal

```bash
# Convert hex balance to decimal USDC
cast to-dec 0x00000000000000000000000000000000000000000000000000000000c4b20100
```

## 📊 Transaction Analysis Commands

### Check Transaction Details

```bash
# Get transaction details
cast tx 0x2bec2428e162f43c7cea265c3164e883fc9e6836fe0dc2181f2bd32d041cf660 --rpc-url https://sepolia.unichain.org

# Get transaction receipt
cast receipt 0x2bec2428e162f43c7cea265c3164e883fc9e6836fe0dc2181f2bd32d041cf660 --rpc-url https://sepolia.unichain.org

# Decode function signature
cast 4byte 0xb6b55f25
```

### Check Error Signatures

```bash
# Decode error signature
cast 4byte 0xfb8f41b2
# Returns: ERC20InsufficientAllowance(address,uint256,uint256)
```

## 🏗️ Contract Addresses

### Unichain Sepolia Testnet

- **Margin Account**: `0x4Aa68070609C7EE42CDd7E431F202c0577c8556E`
- **Mock USDC**: `0xb2feD1a40Fe6CA0be97Cde27e1D2dF1CC65Fd101`
- **Position Manager**: `0xD919D9FA466fD3e88640F97700640fbBb3214eB2`
- **Perps Router**: `0x88e9ae14e9b18417bBdB9e5EA0B836F4DB5093af`
- **Market Manager**: `0x222a07FB1ee309d2e6839e20B384E9DadaAB8D5b`
- **Funding Oracle**: `0xB07387d2ddF33372C9AE9D5aBe8f0850BD54444d`
- **Perps Hook**: `0x06cB25A0F63D88EAED5cb7273d4fab8516B41ac8`
- **Mock VETH**: `0x7f7FD1D6A6BF6225F4872Fc8aa165E43Bf22D30c`
- **Insurance Fund**: `0x4F7a720494f11B7A2e82e9fe7236F09631C9602F`
- **Liquidation Engine**: `0xC037B7cfF8485971E1B1125e7B4Ed1Acc3f6acfd`
- **Position Factory**: `0xFdB6179d9778942Db01C189791c8199350a149e1`

## 📈 Expected Output

### Successful Deposit

```
💰 Margin Account Operations
👤 Using account: 0xcFE743EA353d4d3D2c20C41C7d878B2cbA66DA0a
🏦 Action: deposit
💵 Amount: 15 USDC

💳 Initial USDC Balance: 946795
🏦 Initial Margin Account Balance: 3305
🆓 Initial Free Margin: 2995 USDC
🔒 Initial Locked Margin: 310 USDC

🔐 Approving USDC for MarginAccount...
✅ USDC approved for MarginAccount
💰 Depositing to MarginAccount...
⏳ Waiting for deposit...
🎉 Deposit successful!
📋 Transaction Hash: 0x2bec2428e162f43c7cea265c3164e883fc9e6836fe0dc2181f2bd32d041cf660
📦 Block Number: 31592613n
📊 Transaction Status: success
⏳ Waiting for balances to update...

📊 Updated Balances:
  USDC Balance: 946795 USDC
  Margin Account Balance: 3320 USDC
  Free Margin: 3010 USDC
  Locked Margin: 310 USDC

📈 Balance Changes:
  USDC Change: 0 USDC
  Total Margin Change: +15 USDC
  Free Margin Change: +15 USDC
  Locked Margin Change: 0 USDC
```

## 🔧 Technical Details

### Balance Types

- **USDC Balance**: Your wallet USDC amount
- **Total Margin Balance**: Total USDC in margin account
- **Free Margin**: Available USDC for trading/withdrawal
- **Locked Margin**: USDC locked for active positions

### Transaction Flow

1. **Deposit**: USDC → Free Margin (available for trading)
2. **Withdraw**: Free Margin → USDC wallet
3. **Lock/Unlock**: Free Margin ↔ Locked Margin (for positions)

### Error Handling

- **ERC20InsufficientAllowance**: Need to approve USDC first
- **InsufficientFreeBalance**: Not enough free margin to withdraw
- **InsufficientTotalBalance**: Not enough total margin
- **ZeroAmount**: Cannot deposit/withdraw 0 USDC

## 🛠️ Development

### Using the TypeScript Class

```typescript
import { MarginAccountClient } from "./lib/margin-account";

const client = new MarginAccountClient(
  {
    rpcUrl: "https://sepolia.unichain.org",
    chainId: 1301,
    marginAccountAddress: "0x4Aa68070609C7EE42CDd7E431F202c0577c8556E",
    usdcAddress: "0xb2feD1a40Fe6CA0be97Cde27e1D2dF1CC65Fd101",
  },
  "0x..."
);

// Deposit 100 USDC
await client.deposit(parseUSDC("100"));

// Withdraw 50 USDC
await client.withdraw(parseUSDC("50"));

// Check balances
const totalBalance = await client.getTotalBalance(userAddress);
const freeBalance = await client.getAvailableBalance(userAddress);
const lockedBalance = await client.getLockedBalance(userAddress);
```

### Testing

```bash
# Test deposit
bun run scripts/margin-account.ts deposit 10

# Test withdraw
bun run scripts/margin-account.ts withdraw 5

# Test deposit for another user
bun run scripts/margin-account.ts depositFor 100 0x1234567890123456789012345678901234567890
```

## 🚨 Important Notes

1. **Testnet Only**: This implementation is for Unichain Sepolia testnet
2. **Private Key**: Never commit your private key to version control
3. **Gas Fees**: Transactions require ETH for gas fees
4. **Approval**: USDC must be approved before depositing
5. **Balance Tracking**: The script includes a 3-second delay to ensure accurate balance reading

## 📚 References

- [Viem Documentation](https://viem.sh/)
- [Unichain Documentation](https://docs.unichain.org/)
- [Margin Account Contract](https://github.com/your-repo/uniPerp-ownerNFT)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

MIT License - see LICENSE file for details
