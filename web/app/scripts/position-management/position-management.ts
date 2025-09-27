import "dotenv/config";
import {
  http,
  createWalletClient,
  createPublicClient,
  defineChain,
  encodeAbiParameters,
  keccak256,
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
    "Usage: bun run position-management.ts <action> [amount] [leverage] [tokenId] [percentage]"
  );
  console.log(
    "Actions: openLong, openShort, close, position, balance, addMargin, removeMargin"
  );
  console.log("Examples:");
  console.log(
    "  bun run position-management.ts openLong 100 5  # Open long with 100 USDC, 5x leverage"
  );
  console.log(
    "  bun run position-management.ts openShort 50 3  # Open short with 50 USDC, 3x leverage"
  );
  console.log(
    "  bun run position-management.ts close 1  # Close 100% of position with tokenId 1"
  );
  console.log(
    "  bun run position-management.ts close 1 50  # Close 50% of position with tokenId 1"
  );
  console.log(
    "  bun run position-management.ts addMargin 1 50  # Add 50 USDC margin to position 1"
  );
  console.log(
    "  bun run position-management.ts removeMargin 1 25  # Remove 25 USDC margin from position 1"
  );
  console.log(
    "  bun run position-management.ts position 1  # Get position details for tokenId 1"
  );
  console.log(
    "  bun run position-management.ts balance  # Check margin account balance"
  );
  process.exit(1);
}

const action = args[0]!;
const amount = args[1] ? parseFloat(args[1]) : 0;
const leverage = args[2] ? parseFloat(args[2]) : 1;
const tokenId = args[1] ? parseInt(args[1]) : 0; // For position and close actions, tokenId is the second argument
const closePercentage = args[2] ? parseFloat(args[2]) : 100; // For close action, percentage is the third argument

async function positionManagementOperations() {
  console.log("📈 Position Management Operations");

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
  if (action !== "balance" && action !== "position") {
    console.log("💵 Amount:", amount, "USDC");
    console.log("⚡ Leverage:", leverage, "x");
  }
  if (action === "close" || action === "position") {
    console.log("🆔 Token ID:", tokenId);
  }
  if (action === "close") {
    console.log("📊 Close Percentage:", closePercentage + "%");
  }
  if (action === "addMargin" || action === "removeMargin") {
    console.log("💰 Margin Amount:", amount, "USDC");
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

    // Handle balance check action
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
      return; // Exit early for balance check
    }

    // Handle position details action
    if (action === "position") {
      if (tokenId === 0) {
        throw new Error("Please provide a valid tokenId for position details");
      }

      console.log(`\n📋 Position Details for Token ID ${tokenId}:`);

      try {
        const position = (await publicClient.readContract({
          address: c.positionManager.address,
          abi: c.positionManager.abi as any,
          functionName: "getPosition",
          args: [tokenId],
          blockTag: "latest",
        })) as any;

        console.log(`👤 Owner: ${position.owner}`);
        console.log(`💰 Margin: ${Number(position.margin) / 1e6} USDC`);
        console.log(`🆔 Market ID: ${position.marketId}`);
        console.log(`📊 Size Base: ${position.sizeBase.toString()}`);
        console.log(
          `💲 Entry Price: ${Number(position.entryPrice) / 1e18} USDC`
        );
        console.log(
          `📅 Opened At: ${new Date(
            Number(position.openedAt) * 1000
          ).toISOString()}`
        );
        console.log(
          `📈 Last Funding Index: ${position.lastFundingIndex.toString()}`
        );
        console.log(`💸 Funding Paid: ${position.fundingPaid.toString()}`);

        // Calculate position type and size
        const isLong = position.sizeBase > 0;
        const positionSize = isLong ? position.sizeBase : -position.sizeBase;
        console.log(`📈 Position Type: ${isLong ? "LONG" : "SHORT"}`);
        console.log(`📊 Position Size: ${Number(positionSize) / 1e18} VETH`);

        // Get current mark price and calculate PnL
        try {
          const currentPrice = (await publicClient.readContract({
            address: c.fundingOracle.address,
            abi: c.fundingOracle.abi as any,
            functionName: "getMarkPrice",
            args: [position.marketId],
            blockTag: "latest",
          })) as bigint;

          const unrealizedPnL = (await publicClient.readContract({
            address: c.positionManager.address,
            abi: c.positionManager.abi as any,
            functionName: "getUnrealizedPnL",
            args: [tokenId, currentPrice],
            blockTag: "latest",
          })) as bigint;

          console.log(`💲 Current Price: ${Number(currentPrice) / 1e18} USDC`);
          console.log(`📈 Unrealized PnL: ${Number(unrealizedPnL) / 1e6} USDC`);
        } catch (error) {
          console.log("⚠️  Could not fetch current price or PnL");
        }
      } catch (error) {
        console.error("❌ Error fetching position details:", error);
        throw error;
      }
      return; // Exit early for position details
    }

    // Handle add margin action
    if (action === "addMargin") {
      if (tokenId === 0) {
        throw new Error("Please provide a valid tokenId to add margin");
      }

      if (amount <= 0) {
        throw new Error("Margin amount must be greater than 0");
      }

      // Get position details first
      const position = (await publicClient.readContract({
        address: c.positionManager.address,
        abi: c.positionManager.abi as any,
        functionName: "getPosition",
        args: [tokenId],
        blockTag: "latest",
      })) as any;

      if (position.owner !== account.address) {
        throw new Error("You can only add margin to your own positions");
      }

      console.log("\n📊 Current Position:");
      const currentMargin = Number(position.margin) / 1e6;
      const sizeBase = Number(position.sizeBase) / 1e18;
      const isLong = Number(position.sizeBase) > 0;

      console.log(`  Current Margin: ${currentMargin} USDC`);
      console.log(
        `  Size: ${Math.abs(sizeBase)} VETH (${isLong ? "LONG" : "SHORT"})`
      );
      console.log(`  Adding: ${amount} USDC`);
      console.log(`  New Margin: ${currentMargin + amount} USDC`);

      console.log(`\n🔄 Adding margin to position ${tokenId}...`);

      const addMarginTx = await walletClient.writeContract({
        address: c.positionManager.address,
        abi: c.positionManager.abi as any,
        functionName: "addMargin",
        args: [tokenId, amountWei],
      });

      console.log("⏳ Waiting for margin addition...");
      const receipt = await publicClient.waitForTransactionReceipt({
        hash: addMarginTx,
      });

      console.log("🎉 Margin added successfully!");
      console.log("📋 Transaction Hash:", addMarginTx);
      console.log("📦 Block Number:", receipt.blockNumber);
      console.log("📊 Transaction Status:", receipt.status);

      // Wait for transaction to be fully processed
      await new Promise((resolve) => setTimeout(resolve, 3000));
      return; // Exit early for addMargin
    }

    // Handle remove margin action
    if (action === "removeMargin") {
      if (tokenId === 0) {
        throw new Error("Please provide a valid tokenId to remove margin");
      }

      if (amount <= 0) {
        throw new Error("Margin amount must be greater than 0");
      }

      // Get position details first
      const position = (await publicClient.readContract({
        address: c.positionManager.address,
        abi: c.positionManager.abi as any,
        functionName: "getPosition",
        args: [tokenId],
        blockTag: "latest",
      })) as any;

      if (position.owner !== account.address) {
        throw new Error("You can only remove margin from your own positions");
      }

      console.log("\n📊 Current Position:");
      const currentMargin = Number(position.margin) / 1e6;
      const sizeBase = Number(position.sizeBase) / 1e18;
      const isLong = Number(position.sizeBase) > 0;

      console.log(`  Current Margin: ${currentMargin} USDC`);
      console.log(
        `  Size: ${Math.abs(sizeBase)} VETH (${isLong ? "LONG" : "SHORT"})`
      );
      console.log(`  Removing: ${amount} USDC`);
      console.log(`  New Margin: ${currentMargin - amount} USDC`);

      // Check if removing this amount would violate minimum margin requirement
      if (currentMargin - amount < 100) {
        throw new Error(
          `Cannot remove ${amount} USDC - would leave margin below minimum requirement (100 USDC). Current margin: ${currentMargin} USDC`
        );
      }

      console.log(`\n🔄 Removing margin from position ${tokenId}...`);

      const removeMarginTx = await walletClient.writeContract({
        address: c.positionManager.address,
        abi: c.positionManager.abi as any,
        functionName: "removeMargin",
        args: [tokenId, amountWei],
      });

      console.log("⏳ Waiting for margin removal...");
      const receipt = await publicClient.waitForTransactionReceipt({
        hash: removeMarginTx,
      });

      console.log("🎉 Margin removed successfully!");
      console.log("📋 Transaction Hash:", removeMarginTx);
      console.log("📦 Block Number:", receipt.blockNumber);
      console.log("📊 Transaction Status:", receipt.status);

      // Wait for transaction to be fully processed
      await new Promise((resolve) => setTimeout(resolve, 3000));
      return; // Exit early for removeMargin
    }

    // For position opening, we need to ensure user has margin deposited
    if (action === "openLong" || action === "openShort") {
      if (initialFreeBalance < amountWei) {
        throw new Error(
          `Insufficient free margin balance. Need ${amount} USDC, have ${
            Number(initialFreeBalance) / 1e6
          } USDC. Please deposit margin first.`
        );
      }

      // Build poolKey struct for VETH-USDC pair (same as in your example)
      const fee = 3000; // 0.3%
      const tickSpacing = 60;
      const hooks = c.perpsHook.address;

      // Order currencies by address (lower address = currency0)
      const [currency0, currency1] =
        c.mockUSDC.address.toLowerCase() < c.mockVETH.address.toLowerCase()
          ? [c.mockUSDC.address, c.mockVETH.address]
          : [c.mockVETH.address, c.mockUSDC.address];

      console.log("💱 Pool Configuration:");
      console.log("  Currency0:", currency0);
      console.log("  Currency1:", currency1);
      console.log("  Fee:", fee, "bps");
      console.log("  Hook:", hooks);

      // Calculate poolId using the same method as Uniswap V4
      const poolKeyEncoded = encodeAbiParameters(
        [
          { type: "address", name: "currency0" },
          { type: "address", name: "currency1" },
          { type: "uint24", name: "fee" },
          { type: "int24", name: "tickSpacing" },
          { type: "address", name: "hooks" },
        ],
        [currency0, currency1, fee, tickSpacing, hooks]
      );
      const poolId = keccak256(poolKeyEncoded);

      console.log("🆔 Pool ID:", poolId);

      // Get current mark price
      const markPrice = (await publicClient.readContract({
        address: c.fundingOracle.address,
        abi: c.fundingOracle.abi as any,
        functionName: "getMarkPrice",
        args: [poolId],
        blockTag: "latest",
      })) as bigint;

      console.log(
        "📊 Current Mark Price:",
        Number(markPrice) / 1e18,
        "USDC per VETH"
      );

      // Calculate position size correctly
      const notionalValueUSDC = amount * leverage; // e.g., 100 * 5 = 500 USDC
      const priceUSDCPerVETH = Number(markPrice) / 1e18; // e.g., 2000 USDC per VETH
      const positionSizeVETH = notionalValueUSDC / priceUSDCPerVETH; // e.g., 500 / 2000 = 0.25 VETH

      // Convert to contract units
      const positionSizeWei = BigInt(Math.floor(positionSizeVETH * 1e18)); // VETH has 18 decimals

      console.log("📈 Expected Position Size:", positionSizeVETH, "VETH");
      console.log("💵 Expected Notional Value:", notionalValueUSDC, "USDC");
      console.log("🔢 Position Size Wei:", positionSizeWei.toString());
      console.log("🔢 Margin Wei:", amountWei.toString());

      // Open position via PositionManager
      console.log(
        `\n🔄 Opening ${
          action === "openLong" ? "LONG" : "SHORT"
        } position via PositionManager...`
      );

      const marketId = poolId;
      const sizeBase =
        action === "openLong" ? positionSizeWei : -positionSizeWei;
      const entryPrice = markPrice;
      const margin = amountWei;

      console.log("📋 Position Manager Parameters:");
      console.log("  Market ID:", marketId);
      console.log("  Size Base:", sizeBase.toString());
      console.log("  Entry Price:", entryPrice.toString());
      console.log("  Margin:", margin.toString());

      const openPositionTx = await walletClient.writeContract({
        address: c.positionManager.address,
        abi: c.positionManager.abi as any,
        functionName: "openPosition",
        args: [marketId, sizeBase, entryPrice, margin],
      });

      console.log("⏳ Waiting for position creation...");
      const receipt = await publicClient.waitForTransactionReceipt({
        hash: openPositionTx,
      });

      console.log("🎉 Position opened successfully!");
      console.log("📋 Transaction Hash:", openPositionTx);
      console.log("📦 Block Number:", receipt.blockNumber);
      console.log("📊 Transaction Status:", receipt.status);

      // Try to get the token ID from events
      const logs = receipt.logs;
      console.log("📊 Transaction produced", logs.length, "events");

      // Wait for transaction to be fully processed
      await new Promise((resolve) => setTimeout(resolve, 3000));
    } else if (action === "close") {
      if (tokenId === 0) {
        throw new Error("Please provide a valid tokenId to close position");
      }

      if (closePercentage <= 0 || closePercentage > 100) {
        throw new Error("Close percentage must be between 1 and 100");
      }

      const position = (await publicClient.readContract({
        address: c.positionManager.address,
        abi: c.positionManager.abi as any,
        functionName: "getPosition",
        args: [tokenId],
        blockTag: "latest",
      })) as any;

      if (position.owner !== account.address) {
        throw new Error("You can only close your own positions");
      }

      console.log("\n📊 Current Position:");
      const margin = Number(position.margin) / 1e6;
      const sizeBase = Number(position.sizeBase) / 1e18;
      const entryPrice = Number(position.entryPrice) / 1e18;
      const isLong = Number(position.sizeBase) > 0;

      console.log(`  Margin: ${margin} USDC`);
      console.log(
        `  Size: ${Math.abs(sizeBase)} VETH (${isLong ? "LONG" : "SHORT"})`
      );
      console.log(`  Entry Price: ${entryPrice} USDC per VETH`);

      // Get current mark price for closing
      const currentPrice = (await publicClient.readContract({
        address: c.fundingOracle.address,
        abi: c.fundingOracle.abi as any,
        functionName: "getMarkPrice",
        args: [position.marketId],
        blockTag: "latest",
      })) as bigint;

      const markPriceFormatted = Number(currentPrice) / 1e18;
      console.log(`💲 Current Mark Price: ${markPriceFormatted} USDC per VETH`);

      // Calculate PnL before closing
      let unrealizedPnL = 0;
      if (isLong) {
        unrealizedPnL = Math.abs(sizeBase) * (markPriceFormatted - entryPrice);
      } else {
        unrealizedPnL = Math.abs(sizeBase) * (entryPrice - markPriceFormatted);
      }

      const pnlPercent = (unrealizedPnL / margin) * 100;
      const pnlColor = unrealizedPnL >= 0 ? "🟢" : "🔴";

      console.log("\n📈 Expected PnL:");
      console.log(
        `  Unrealized PnL: ${pnlColor} ${
          unrealizedPnL >= 0 ? "+" : ""
        }${unrealizedPnL.toFixed(2)} USDC`
      );
      console.log(
        `  PnL %: ${pnlColor} ${
          unrealizedPnL >= 0 ? "+" : ""
        }${pnlPercent.toFixed(2)}%`
      );

      console.log(`\n🔄 Closing ${closePercentage}% of position ${tokenId}...`);

      let closeTx;
      if (closePercentage === 100) {
        // Full closure - use closePosition function
        closeTx = await walletClient.writeContract({
          address: c.positionManager.address,
          abi: c.positionManager.abi as any,
          functionName: "closePosition",
          args: [tokenId, BigInt(Math.floor(markPriceFormatted * 1e18))],
        });
      } else {
        // Partial closure - use updatePosition function
        const newSizeBase = sizeBase * (1 - closePercentage / 100);
        const newMargin = margin * (1 - closePercentage / 100);

        console.log(`📊 Partial Close Calculation:`);
        console.log(`  Original Size: ${sizeBase} VETH`);
        console.log(`  New Size: ${newSizeBase} VETH`);
        console.log(`  Original Margin: ${margin} USDC`);
        console.log(`  New Margin: ${newMargin} USDC`);

        // Check if new margin meets minimum requirement (100 USDC)
        if (newMargin < 100) {
          throw new Error(
            `Cannot close ${closePercentage}% - remaining margin (${newMargin} USDC) would be below minimum requirement (100 USDC). Try closing less or close the entire position.`
          );
        }

        closeTx = await walletClient.writeContract({
          address: c.positionManager.address,
          abi: c.positionManager.abi as any,
          functionName: "updatePosition",
          args: [
            tokenId,
            BigInt(Math.floor(newSizeBase * 1e18)), // new size
            BigInt(Math.floor(newMargin * 1e6)), // new margin
          ],
        });
      }

      console.log("⏳ Waiting for position closure...");
      const receipt = await publicClient.waitForTransactionReceipt({
        hash: closeTx,
      });

      console.log("🎉 Position closed successfully!");
      console.log("📋 Transaction Hash:", closeTx);
      console.log("📦 Block Number:", receipt.blockNumber);
      console.log("📊 Transaction Status:", receipt.status);

      if (closePercentage === 100) {
        console.log("✅ Position fully closed");
      } else {
        console.log(`✅ ${closePercentage}% of position closed`);

        // Show remaining position
        try {
          const remainingPosition = (await publicClient.readContract({
            address: c.positionManager.address,
            abi: c.positionManager.abi as any,
            functionName: "getPosition",
            args: [tokenId],
            blockTag: "latest",
          })) as any;

          const remainingSize = Number(remainingPosition.sizeBase) / 1e18;
          const remainingMargin = Number(remainingPosition.margin) / 1e6;

          console.log("\n📊 Remaining Position:");
          console.log(`  Size: ${Math.abs(remainingSize)} VETH`);
          console.log(`  Margin: ${remainingMargin} USDC`);
        } catch (error) {
          console.log("ℹ️  Position might be fully closed");
        }
      }

      // Wait for transaction to be fully processed
      await new Promise((resolve) => setTimeout(resolve, 3000));
    } else {
      throw new Error(
        `Invalid action: ${action}. Use openLong, openShort, close, position, balance, addMargin, or removeMargin`
      );
    }

    // Wait for transaction to be fully processed before reading updated balances
    console.log("⏳ Waiting for balances to update...");
    await new Promise((resolve) => setTimeout(resolve, 3000));

    // Get updated balances after operation
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

positionManagementOperations().catch((e) => {
  console.error("💥 Failed:", e);
  process.exit(1);
});
