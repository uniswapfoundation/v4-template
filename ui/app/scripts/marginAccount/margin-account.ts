import "dotenv/config";
import {
  http,
  createWalletClient,
  createPublicClient,
  defineChain,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { getContracts, UNICHAIN_SEPOLIA } from "../contracts";

const RPC_URL =
  process.env.RPC_URL ||
  process.env.UNICHAIN_SEPOLIA_RPC_URL ||
  "https://sepolia.unichain.org";
const CHAIN_ID = Number(process.env.CHAIN_ID || UNICHAIN_SEPOLIA);
// Use the provided private key or fallback to environment variable
const PK = "0xcf43b326c9b11208da2d1f0d36b97a54af487e07ff56f22536bfa29a1ba35644";
if (!PK || PK.length < 10) throw new Error("PRIVATE_KEY missing");

// Get command line arguments
const args = process.argv.slice(2);
if (args.length < 1) {
  console.log(
    "Usage: bun run margin-account.ts <action> [amount] [userAddress]"
  );
  console.log(
    "Actions: deposit, withdraw, depositFor, withdrawFor, balance, usdc"
  );
  console.log(
    "Example: bun run margin-account.ts deposit 100  # Deposit 100 USDC"
  );
  console.log(
    "Example: bun run margin-account.ts depositFor 100 0x123...  # Deposit 100 USDC for user"
  );
  console.log(
    "Example: bun run margin-account.ts balance  # Check current free and locked margin"
  );
  console.log(
    "Example: bun run margin-account.ts usdc  # Check USDC wallet balance only"
  );
  process.exit(1);
}

const action = args[0]!;
const amount = args[1] ? parseFloat(args[1]) : 0;
const userAddress = args[2] as `0x${string}` | undefined;

async function marginAccountOperations() {
  console.log("💰 Margin Account Operations");

  const account = privateKeyToAccount(PK as `0x${string}`);
  const chain = defineChain({
    id: CHAIN_ID,
    name: "UnichainSepolia",
    nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 },
    rpcUrls: {
      default: { http: [RPC_URL] },
      public: { http: [RPC_URL] },
    },
  });

  const transport = http(RPC_URL);
  const publicClient = createPublicClient({ transport, chain });
  const walletClient = createWalletClient({ account, transport, chain });
  const c = getContracts(CHAIN_ID);

  console.log("👤 Using account:", account.address);
  console.log("🏦 Action:", action);
  if (action !== "balance") {
    console.log("💵 Amount:", amount, "USDC");
    if (userAddress) console.log("👥 Target user:", userAddress);
  }

  try {
    // Convert amount to wei (6 decimals for USDC)
    const amountWei = BigInt(Math.floor(amount * 1e6));

    // Check current balances before any operations
    const initialUsdcBalance = (await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: "balanceOf",
      args: [account.address],
      blockTag: "latest",
    })) as bigint;

    const initialMarginAccountBalance = (await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: "getTotalBalance",
      args: [account.address],
      blockTag: "latest",
    })) as bigint;

    const initialFreeBalance = (await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: "freeBalance",
      args: [account.address],
      blockTag: "latest",
    })) as bigint;

    const initialLockedBalance = (await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: "lockedBalance",
      args: [account.address],
      blockTag: "latest",
    })) as bigint;

    console.log(
      `\n💳 Initial USDC Balance: ${Number(initialUsdcBalance) / 1e6}`
    );
    console.log(
      `🏦 Initial Margin Account Balance: ${
        Number(initialMarginAccountBalance) / 1e6
      }`
    );
    console.log(
      `🆓 Initial Free Margin: ${Number(initialFreeBalance) / 1e6} USDC`
    );
    console.log(
      `🔒 Initial Locked Margin: ${Number(initialLockedBalance) / 1e6} USDC`
    );

    // Handle balance check actions
    if (action === "balance") {
      console.log("\n📊 Current Margin Account Status:");
      console.log(
        `💳 USDC Wallet Balance: ${Number(initialUsdcBalance) / 1e6} USDC`
      );
      console.log(
        `🏦 Total Margin Account Balance: ${
          Number(initialMarginAccountBalance) / 1e6
        } USDC`
      );
      console.log(`🆓 Free Margin: ${Number(initialFreeBalance) / 1e6} USDC`);
      console.log(
        `🔒 Locked Margin: ${Number(initialLockedBalance) / 1e6} USDC`
      );
      console.log(
        `📈 Available for Trading: ${Number(initialFreeBalance) / 1e6} USDC`
      );
      console.log(
        `💰 Total Account Value: ${
          Number(initialMarginAccountBalance) / 1e6
        } USDC`
      );
      return; // Exit early for balance check
    }

    if (action === "usdc") {
      console.log("\n💳 USDC Wallet Balance Check:");
      console.log(`🏦 Network: Unichain Sepolia (Chain ID: ${CHAIN_ID})`);
      console.log(`👤 Account: ${account.address}`);
      console.log(`💵 USDC Balance: ${Number(initialUsdcBalance) / 1e6} USDC`);
      console.log(`🔗 USDC Contract: ${c.mockUSDC.address}`);
      console.log(`🌐 RPC URL: ${RPC_URL}`);
      return; // Exit early for USDC check
    }

    if (action === "deposit" || action === "depositFor") {
      if (initialUsdcBalance < amountWei) {
        throw new Error(
          `Insufficient USDC balance. Need ${amount} USDC, have ${
            Number(initialUsdcBalance) / 1e6
          } USDC`
        );
      }

      // Step 1: Approve USDC for MarginAccount
      console.log("\n🔐 Approving USDC for MarginAccount...");

      const approveTx = await walletClient.writeContract({
        address: c.mockUSDC.address,
        abi: c.mockUSDC.abi as any,
        functionName: "approve",
        args: [c.marginAccount.address, amountWei],
      });

      await publicClient.waitForTransactionReceipt({ hash: approveTx });
      console.log("✅ USDC approved for MarginAccount");

      // Step 2: Deposit to MarginAccount
      console.log("💰 Depositing to MarginAccount...");

      let depositTx: `0x${string}`;
      if (action === "depositFor" && userAddress) {
        depositTx = await walletClient.writeContract({
          address: c.marginAccount.address,
          abi: c.marginAccount.abi as any,
          functionName: "depositFor",
          args: [userAddress, amountWei],
        });
      } else {
        depositTx = await walletClient.writeContract({
          address: c.marginAccount.address,
          abi: c.marginAccount.abi as any,
          functionName: "deposit",
          args: [amountWei],
        });
      }

      console.log("⏳ Waiting for deposit...");
      const receipt = await publicClient.waitForTransactionReceipt({
        hash: depositTx,
      });

      console.log("🎉 Deposit successful!");
      console.log("📋 Transaction Hash:", depositTx);
      console.log("📦 Block Number:", receipt.blockNumber);
      console.log("📊 Transaction Status:", receipt.status);

      // Check if transaction was successful
      if (receipt.status !== "success") {
        throw new Error(`Transaction failed with status: ${receipt.status}`);
      }

      // Wait a bit for the transaction to be fully processed
      await new Promise((resolve) => setTimeout(resolve, 2000));
    } else if (action === "withdraw" || action === "withdrawFor") {
      if (initialMarginAccountBalance < amountWei) {
        throw new Error(
          `Insufficient margin account balance. Need ${amount} USDC, have ${
            Number(initialMarginAccountBalance) / 1e6
          } USDC`
        );
      }

      // Withdraw from MarginAccount
      console.log("💸 Withdrawing from MarginAccount...");

      let withdrawTx: `0x${string}`;
      if (action === "withdrawFor" && userAddress) {
        withdrawTx = await walletClient.writeContract({
          address: c.marginAccount.address,
          abi: c.marginAccount.abi as any,
          functionName: "withdrawFor",
          args: [userAddress, amountWei],
        });
      } else {
        withdrawTx = await walletClient.writeContract({
          address: c.marginAccount.address,
          abi: c.marginAccount.abi as any,
          functionName: "withdraw",
          args: [amountWei],
        });
      }

      console.log("⏳ Waiting for withdrawal...");
      const receipt = await publicClient.waitForTransactionReceipt({
        hash: withdrawTx,
      });

      console.log("🎉 Withdrawal successful!");
      console.log("📋 Transaction Hash:", withdrawTx);
      console.log("📦 Block Number:", receipt.blockNumber);

      // Wait a bit for the transaction to be fully processed
      await new Promise((resolve) => setTimeout(resolve, 2000));
    } else {
      throw new Error(
        `Invalid action: ${action}. Use deposit, withdraw, depositFor, or withdrawFor`
      );
    }

    // Wait for transaction to be fully processed before reading updated balances
    console.log("⏳ Waiting for balances to update...");
    await new Promise((resolve) => setTimeout(resolve, 3000));

    // Get updated balances after operation - force latest block
    const updatedUsdcBalance = (await publicClient.readContract({
      address: c.mockUSDC.address,
      abi: c.mockUSDC.abi as any,
      functionName: "balanceOf",
      args: [account.address],
      blockTag: "latest",
    })) as bigint;

    const updatedMarginAccountBalance = (await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: "getTotalBalance",
      args: [account.address],
      blockTag: "latest",
    })) as bigint;

    const updatedFreeBalance = (await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: "freeBalance",
      args: [account.address],
      blockTag: "latest",
    })) as bigint;

    const updatedLockedBalance = (await publicClient.readContract({
      address: c.marginAccount.address,
      abi: c.marginAccount.abi as any,
      functionName: "lockedBalance",
      args: [account.address],
      blockTag: "latest",
    })) as bigint;

    console.log("\n📊 Updated Balances:");
    console.log(`  USDC Balance: ${Number(updatedUsdcBalance) / 1e6} USDC`);
    console.log(
      `  Margin Account Balance: ${
        Number(updatedMarginAccountBalance) / 1e6
      } USDC`
    );
    console.log(`  Free Margin: ${Number(updatedFreeBalance) / 1e6} USDC`);
    console.log(`  Locked Margin: ${Number(updatedLockedBalance) / 1e6} USDC`);

    console.log("\n🔍 Debug Info:");
    console.log(`  Initial USDC: ${Number(initialUsdcBalance) / 1e6} USDC`);
    console.log(`  Final USDC: ${Number(updatedUsdcBalance) / 1e6} USDC`);
    console.log(
      `  Initial Total Margin: ${
        Number(initialMarginAccountBalance) / 1e6
      } USDC`
    );
    console.log(
      `  Final Total Margin: ${Number(updatedMarginAccountBalance) / 1e6} USDC`
    );
    console.log(
      `  Initial Free Margin: ${Number(initialFreeBalance) / 1e6} USDC`
    );
    console.log(
      `  Final Free Margin: ${Number(updatedFreeBalance) / 1e6} USDC`
    );
    console.log(
      `  Initial Locked Margin: ${Number(initialLockedBalance) / 1e6} USDC`
    );
    console.log(
      `  Final Locked Margin: ${Number(updatedLockedBalance) / 1e6} USDC`
    );

    // Show balance changes
    const usdcChange = Number(updatedUsdcBalance - initialUsdcBalance) / 1e6;
    const marginChange =
      Number(updatedMarginAccountBalance - initialMarginAccountBalance) / 1e6;
    const freeMarginChange =
      Number(updatedFreeBalance - initialFreeBalance) / 1e6;
    const lockedMarginChange =
      Number(updatedLockedBalance - initialLockedBalance) / 1e6;

    console.log("\n📈 Balance Changes:");
    console.log(
      `  USDC Change: ${usdcChange > 0 ? "+" : ""}${usdcChange} USDC`
    );
    console.log(
      `  Total Margin Change: ${
        marginChange > 0 ? "+" : ""
      }${marginChange} USDC`
    );
    console.log(
      `  Free Margin Change: ${
        freeMarginChange > 0 ? "+" : ""
      }${freeMarginChange} USDC`
    );
    console.log(
      `  Locked Margin Change: ${
        lockedMarginChange > 0 ? "+" : ""
      }${lockedMarginChange} USDC`
    );
  } catch (error) {
    console.error("❌ Error:", error);
    throw error;
  }
}

marginAccountOperations().catch((e) => {
  console.error("💥 Failed:", e);
  process.exit(1);
});
