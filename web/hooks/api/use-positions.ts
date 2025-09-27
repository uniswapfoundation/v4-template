import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { createPublicClient, http, defineChain } from "viem";
import { parseUnits, formatUnits, encodeAbiParameters, keccak256 } from "viem";
import { getContracts, UNICHAIN_SEPOLIA } from "@/lib/core";

// Types
export interface Position {
  tokenId: string;
  owner: string;
  margin: number; // in USDC
  marketId: string;
  sizeBase: number; // in VETH
  entryPrice: number; // in USDC
  openedAt: string;
  isLong: boolean;
  currentPrice: number;
  notionalValue: number;
  currentNotional: number;
  leverage: number;
  unrealizedPnL: number;
  pnlPercentage: number;
  liquidationPrice: number;
  distanceToLiquidation: number;
}

export interface AccountBalance {
  walletUSDC: number;
  freeMargin: number;
  lockedMargin: number;
  totalMargin: number;
}

export interface PositionsWithBalance {
  positions: Position[];
  accountBalance: AccountBalance;
  currentMarkPrice: number;
}

export interface CreatePositionParams {
  marketId: string;
  size: number; // Size in base asset (e.g., ETH)
  leverage: number;
  margin: number; // Margin in USDC
  isLong: boolean;
}

export interface ClosePositionParams {
  tokenId: string;
  exitPrice?: number; // Optional, will fetch current price if not provided
  percentage?: number; // Optional, percentage to close (1-100), defaults to 100
}

export interface MarginOperationParams {
  tokenId: string;
  amount: number; // Amount in USDC
}

// Query Keys
export const positionKeys = {
  all: ["positions"] as const,
  withBalance: (address: string) =>
    [...positionKeys.all, "withBalance", address] as const,
  open: () => [...positionKeys.all, "open"] as const,
  detail: (tokenId: string) =>
    [...positionKeys.all, "detail", tokenId] as const,
  markPrice: (poolId: string) =>
    [...positionKeys.all, "markPrice", poolId] as const,
};

// Utility functions
export function calculatePoolId(
  currency0: `0x${string}`,
  currency1: `0x${string}`,
  fee: number = 3000,
  tickSpacing: number = 60,
  hooks: `0x${string}`
): `0x${string}` {
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
  return keccak256(poolKeyEncoded);
}

export function calculatePositionSize(
  margin: number,
  leverage: number,
  price: number
): number {
  const notionalValue = margin * leverage;
  return notionalValue / price;
}

// Main hook for positions with balance (most commonly used)
export function usePositionsWithBalance() {
  const { address } = useAccount();

  const query = useQuery({
    queryKey: positionKeys.withBalance(address || ""),
    queryFn: async (): Promise<PositionsWithBalance> => {
      if (!address) {
        return {
          positions: [],
          accountBalance: {
            walletUSDC: 0,
            freeMargin: 0,
            lockedMargin: 0,
            totalMargin: 0,
          },
          currentMarkPrice: 0,
        };
      }

      try {
        // Setup blockchain connection
        const RPC_URL =
          process.env.NEXT_PUBLIC_UNICHAIN_SEPOLIA_RPC_URL ||
          "https://sepolia.unichain.org";

        const chain = defineChain({
          id: UNICHAIN_SEPOLIA,
          name: "UnichainSepolia",
          nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 },
          rpcUrls: {
            default: { http: [RPC_URL] },
            public: { http: [RPC_URL] },
          },
        });

        const transport = http(RPC_URL);
        const publicClient = createPublicClient({ transport, chain });
        const contracts = getContracts(UNICHAIN_SEPOLIA);

        // Get user positions
        const userPositions = (await publicClient.readContract({
          address: contracts.positionManager.address,
          abi: contracts.positionManager.abi as any,
          functionName: "getUserPositions",
          args: [address as `0x${string}`],
        })) as bigint[];

        console.log(`🔍 Found ${userPositions.length} position(s)`);

        // Get current mark price
        const markPrice = (await publicClient.readContract({
          address: contracts.fundingOracle.address,
          abi: contracts.fundingOracle.abi as any,
          functionName: "getMarkPrice",
          args: [
            "0xdb86d006b7f5ba7afb160f08da976bf53d7254e25da80f1dda0a5d36d26d656d",
          ],
        })) as bigint;

        const currentMarkPrice = Number(markPrice) / 1e18;
        console.log(`📊 Current Mark Price: ${currentMarkPrice} USDC per VETH`);

        const positions: Position[] = [];

        // Process each position
        for (let i = 0; i < userPositions.length; i++) {
          const tokenId = userPositions[i];

          try {
            // Get position details
            const position = (await publicClient.readContract({
              address: contracts.positionManager.address,
              abi: contracts.positionManager.abi as any,
              functionName: "getPosition",
              args: [tokenId],
            })) as any;

            const sizeBase = Number(position.sizeBase) / 1e18;
            const entryPrice = Number(position.entryPrice) / 1e18;
            const margin = Number(position.margin) / 1e6;
            const isLong = Number(position.sizeBase) > 0;

            // Filter out empty positions (owner is 0x0000...)
            if (
              position.owner === "0x0000000000000000000000000000000000000000"
            ) {
              continue;
            }

            // Calculate metrics
            const notionalValue = Math.abs(sizeBase) * entryPrice;
            const currentNotional = Math.abs(sizeBase) * currentMarkPrice;
            const leverage = notionalValue / margin;

            // Calculate PnL
            let unrealizedPnL = 0;
            if (isLong) {
              unrealizedPnL =
                Math.abs(sizeBase) * (currentMarkPrice - entryPrice);
            } else {
              unrealizedPnL =
                Math.abs(sizeBase) * (entryPrice - currentMarkPrice);
            }
            const pnlPercentage = (unrealizedPnL / margin) * 100;

            // Calculate liquidation price
            const liquidationThreshold = margin * 0.8; // 80% maintenance margin
            let liquidationPrice = 0;
            if (isLong) {
              liquidationPrice =
                entryPrice - liquidationThreshold / Math.abs(sizeBase);
            } else {
              liquidationPrice =
                entryPrice + liquidationThreshold / Math.abs(sizeBase);
            }

            positions.push({
              tokenId: tokenId.toString(),
              owner: position.owner,
              margin,
              marketId: position.marketId,
              sizeBase: Math.abs(sizeBase),
              entryPrice,
              openedAt: new Date(
                Number(position.openedAt) * 1000
              ).toISOString(),
              isLong,
              currentPrice: currentMarkPrice,
              notionalValue,
              currentNotional,
              leverage,
              unrealizedPnL,
              pnlPercentage,
              liquidationPrice,
              distanceToLiquidation: Math.abs(
                currentMarkPrice - liquidationPrice
              ),
            });
          } catch (error) {
            console.error(`Error processing position ${tokenId}:`, error);
            // Skip invalid positions
            continue;
          }
        }

        // Get account balance info
        const usdcBalance = (await publicClient.readContract({
          address: contracts.mockUSDC.address,
          abi: contracts.mockUSDC.abi as any,
          functionName: "balanceOf",
          args: [address as `0x${string}`],
        })) as bigint;

        const freeBalance = (await publicClient.readContract({
          address: contracts.marginAccount.address,
          abi: contracts.marginAccount.abi as any,
          functionName: "freeBalance",
          args: [address as `0x${string}`],
        })) as bigint;

        const lockedBalance = (await publicClient.readContract({
          address: contracts.marginAccount.address,
          abi: contracts.marginAccount.abi as any,
          functionName: "lockedBalance",
          args: [address as `0x${string}`],
        })) as bigint;

        const accountBalance: AccountBalance = {
          walletUSDC: Number(usdcBalance) / 1e6,
          freeMargin: Number(freeBalance) / 1e6,
          lockedMargin: Number(lockedBalance) / 1e6,
          totalMargin: Number(freeBalance + lockedBalance) / 1e6,
        };

        console.log(`💰 Wallet USDC: ${accountBalance.walletUSDC} USDC`);
        console.log(`🆓 Free Margin: ${accountBalance.freeMargin} USDC`);
        console.log(`🔒 Locked Margin: ${accountBalance.lockedMargin} USDC`);
        console.log(`💯 Total Margin: ${accountBalance.totalMargin} USDC`);

        return {
          positions,
          accountBalance,
          currentMarkPrice,
        };
      } catch (error) {
        console.error("Error fetching positions with balance:", error);
        return {
          positions: [],
          accountBalance: {
            walletUSDC: 0,
            freeMargin: 0,
            lockedMargin: 0,
            totalMargin: 0,
          },
          currentMarkPrice: 0,
        };
      }
    },
    enabled: !!address,
    refetchInterval: false, // No automatic polling - only refetch on invalidation
    staleTime: 30 * 1000, // Consider data stale after 30 seconds
    gcTime: 5 * 60 * 1000, // Keep in cache for 5 minutes
    refetchOnWindowFocus: false, // Don't refetch on window focus
    refetchOnMount: true, // Refetch when component mounts
    retry: 3, // Retry failed requests 3 times
    retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 30000), // Exponential backoff
  });

  return {
    ...query,
    refetchPositions: query.refetch, // Expose manual refetch function
  };
}

// Position management hooks
export function useOpenPosition() {
  const { writeContractAsync } = useWriteContract();
  const queryClient = useQueryClient();
  const { address } = useAccount();

  return useMutation({
    mutationFn: async (params: CreatePositionParams) => {
      console.log("📝 Position management hook called with params:", params);

      if (!address) throw new Error("Wallet not connected");

      const contracts = getContracts(UNICHAIN_SEPOLIA);
      console.log("📋 Contract addresses:", contracts);

      // Create public client for reading contract data (same as working script)
      const RPC_URL =
        process.env.NEXT_PUBLIC_UNICHAIN_SEPOLIA_RPC_URL ||
        "https://sepolia.unichain.org";
      const chain = defineChain({
        id: UNICHAIN_SEPOLIA,
        name: "UnichainSepolia",
        nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 },
        rpcUrls: {
          default: { http: [RPC_URL] },
          public: { http: [RPC_URL] },
        },
      });
      const transport = http(RPC_URL);
      const publicClient = createPublicClient({ transport, chain });

      // Calculate pool ID using the exact same method as the working script
      const fee = 3000; // 0.3%
      const tickSpacing = 60;
      const hooks = contracts.perpsHook.address;

      // Order currencies by address (lower address = currency0) - same as script
      const [currency0, currency1] =
        contracts.mockUSDC.address.toLowerCase() <
        contracts.mockVETH.address.toLowerCase()
          ? [contracts.mockUSDC.address, contracts.mockVETH.address]
          : [contracts.mockVETH.address, contracts.mockUSDC.address];

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
      console.log("🆔 Calculated pool ID:", poolId);

      // Get current mark price from oracle (same as working script)
      const markPrice = (await publicClient.readContract({
        address: contracts.fundingOracle.address,
        abi: [
          {
            inputs: [{ name: "poolId", type: "bytes32" }],
            name: "getMarkPrice",
            outputs: [{ name: "", type: "uint256" }],
            stateMutability: "view",
            type: "function",
          },
        ],
        functionName: "getMarkPrice",
        args: [poolId],
      })) as bigint;

      const entryPrice = markPrice;
      const priceUSDCPerVETH = Number(formatUnits(markPrice, 18));

      console.log("📊 Current Mark Price:", priceUSDCPerVETH, "USDC per VETH");

      // Calculate position size using the same method as working script
      const notionalValueUSDC = params.margin * params.leverage;
      const positionSizeVETH = notionalValueUSDC / priceUSDCPerVETH;

      // Convert to contract units (same as working script)
      const positionSizeWei = BigInt(Math.floor(positionSizeVETH * 1e18));
      const margin = parseUnits(params.margin.toString(), 6); // USDC has 6 decimals

      console.log("📈 Expected Position Size:", positionSizeVETH, "VETH");
      console.log("💵 Expected Notional Value:", notionalValueUSDC, "USDC");
      console.log("🔢 Position Size Wei:", positionSizeWei.toString());
      console.log("🔢 Margin Wei:", margin.toString());

      console.log("📝 Calling contract with parameters:");
      console.log("  Contract Address:", contracts.positionManager.address);
      console.log("  Pool ID:", poolId);
      console.log(
        "  Size Base:",
        params.isLong ? positionSizeWei : -positionSizeWei
      );
      console.log("  Entry Price:", entryPrice);
      console.log("  Margin:", margin);
      console.log("  Is Long:", params.isLong);

      const txHash = await writeContractAsync({
        address: contracts.positionManager.address,
        abi: [
          {
            inputs: [
              { name: "marketId", type: "bytes32" },
              { name: "sizeBase", type: "int256" },
              { name: "entryPrice", type: "uint256" },
              { name: "margin", type: "uint256" },
            ],
            name: "openPosition",
            outputs: [{ name: "", type: "uint256" }],
            stateMutability: "nonpayable",
            type: "function",
          },
        ],
        functionName: "openPosition",
        args: [
          poolId,
          params.isLong ? positionSizeWei : -positionSizeWei,
          entryPrice,
          margin,
        ],
      });

      console.log("✅ Contract call successful! Transaction hash:", txHash);
      return { txHash, poolId };
    },
    onSuccess: () => {
      // Invalidate position queries to trigger refetch
      queryClient.invalidateQueries({
        queryKey: positionKeys.withBalance(address || ""),
        exact: true,
      });
      console.log("🔄 Position data invalidated after position open");
    },
  });
}

export function useClosePosition() {
  const { writeContractAsync } = useWriteContract();
  const queryClient = useQueryClient();
  const { address } = useAccount();

  // Create public client for reading contract data
  const publicClient = createPublicClient({
    chain: {
      id: UNICHAIN_SEPOLIA,
      name: "UnichainSepolia",
      nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 },
      rpcUrls: {
        default: { http: ["https://sepolia.unichain.org"] },
        public: { http: ["https://sepolia.unichain.org"] },
      },
    },
    transport: http("https://sepolia.unichain.org"),
  });

  return useMutation({
    mutationFn: async (params: ClosePositionParams) => {
      if (!address) throw new Error("Wallet not connected");

      const contracts = getContracts(UNICHAIN_SEPOLIA);
      const percentage = params.percentage || 100; // Default to 100% if not provided

      // Validate percentage
      if (percentage <= 0 || percentage > 100) {
        throw new Error("Close percentage must be between 1 and 100");
      }

      // Get current mark price if not provided
      let exitPrice = params.exitPrice;
      if (!exitPrice) {
        // In production, fetch from oracle
        exitPrice = 2000; // Mock price
      }

      let txHash: `0x${string}`;

      if (percentage === 100) {
        // Full closure - use closePosition function
        txHash = await writeContractAsync({
          address: contracts.positionManager.address,
          abi: [
            {
              inputs: [
                { name: "tokenId", type: "uint256" },
                { name: "exitPrice", type: "uint256" },
              ],
              name: "closePosition",
              outputs: [],
              stateMutability: "nonpayable",
              type: "function",
            },
          ],
          functionName: "closePosition",
          args: [BigInt(params.tokenId), parseUnits(exitPrice.toString(), 18)],
        });
      } else {
        // Partial closure - use updatePosition function
        console.log(
          `Partial closing ${percentage}% of position ${params.tokenId}`
        );

        // Fetch current position details first
        const currentPosition = (await publicClient.readContract({
          address: contracts.positionManager.address,
          abi: [
            {
              inputs: [{ name: "tokenId", type: "uint256" }],
              name: "getPosition",
              outputs: [
                {
                  components: [
                    { name: "owner", type: "address" },
                    { name: "margin", type: "uint96" },
                    { name: "marketId", type: "bytes32" },
                    { name: "sizeBase", type: "int256" },
                    { name: "entryPrice", type: "uint256" },
                    { name: "lastFundingIndex", type: "uint256" },
                    { name: "openedAt", type: "uint64" },
                    { name: "fundingPaid", type: "int256" },
                  ],
                  name: "",
                  type: "tuple",
                },
              ],
              stateMutability: "view",
              type: "function",
            },
          ],
          functionName: "getPosition",
          args: [BigInt(params.tokenId)],
        })) as any;

        if (!currentPosition) {
          throw new Error("Position not found");
        }

        // Calculate new size and margin based on percentage
        const currentSize = Number(currentPosition.sizeBase);
        const currentMargin = Number(currentPosition.margin);
        const newSizePercentage = (100 - percentage) / 100;

        const newSize = BigInt(Math.floor(currentSize * newSizePercentage));
        const newMargin = BigInt(Math.floor(currentMargin * newSizePercentage));

        console.log("Partial close calculation:", {
          currentSize: currentSize / 1e18,
          currentMargin: currentMargin / 1e6,
          newSize: Number(newSize) / 1e18,
          newMargin: Number(newMargin) / 1e6,
          percentage,
        });

        // Check if new margin meets minimum requirement (100 USDC)
        if (Number(newMargin) / 1e6 < 100) {
          throw new Error(
            `Cannot close ${percentage}% - remaining margin would be below minimum requirement (100 USDC)`
          );
        }

        txHash = await writeContractAsync({
          address: contracts.positionManager.address,
          abi: [
            {
              inputs: [
                { name: "tokenId", type: "uint256" },
                { name: "newSizeBase", type: "int256" },
                { name: "newMargin", type: "uint256" },
              ],
              name: "updatePosition",
              outputs: [],
              stateMutability: "nonpayable",
              type: "function",
            },
          ],
          functionName: "updatePosition",
          args: [BigInt(params.tokenId), newSize, newMargin],
        });
      }

      return { txHash, percentage };
    },
    onSuccess: () => {
      // Invalidate position queries to trigger refetch
      queryClient.invalidateQueries({
        queryKey: positionKeys.withBalance(address || ""),
        exact: true,
      });
      console.log("🔄 Position data invalidated after position close");
    },
  });
}

// Margin operations for positions
export function useAddMargin() {
  const { writeContractAsync } = useWriteContract();
  const queryClient = useQueryClient();
  const { address } = useAccount();

  return useMutation({
    mutationFn: async (params: MarginOperationParams) => {
      if (!address) throw new Error("Wallet not connected");

      const contracts = getContracts(UNICHAIN_SEPOLIA);
      const amount = parseUnits(params.amount.toString(), 6); // USDC has 6 decimals

      console.log("💰 Adding margin to position:", {
        tokenId: params.tokenId,
        amount: params.amount,
      });

      // Call positionManager.addMargin instead of marginAccount.deposit
      const txHash = await writeContractAsync({
        address: contracts.positionManager.address,
        abi: [
          {
            inputs: [
              { name: "tokenId", type: "uint256" },
              { name: "amount", type: "uint256" },
            ],
            name: "addMargin",
            outputs: [],
            stateMutability: "nonpayable",
            type: "function",
          },
        ],
        functionName: "addMargin",
        args: [BigInt(params.tokenId), amount],
      });

      console.log("✅ Margin added to position! Transaction hash:", txHash);
      return { txHash, amount: params.amount };
    },
    onSuccess: () => {
      // Invalidate position queries to trigger refetch
      queryClient.invalidateQueries({
        queryKey: positionKeys.withBalance(address || ""),
        exact: true,
      });
      console.log("🔄 Position data invalidated after margin add");
    },
  });
}

export function useRemoveMargin() {
  const { writeContractAsync } = useWriteContract();
  const queryClient = useQueryClient();
  const { address } = useAccount();

  return useMutation({
    mutationFn: async (params: MarginOperationParams) => {
      if (!address) throw new Error("Wallet not connected");

      const contracts = getContracts(UNICHAIN_SEPOLIA);
      const amount = parseUnits(params.amount.toString(), 6); // USDC has 6 decimals

      console.log("💰 Removing margin from position:", {
        tokenId: params.tokenId,
        amount: params.amount,
      });

      // Call positionManager.removeMargin instead of marginAccount.withdraw
      const txHash = await writeContractAsync({
        address: contracts.positionManager.address,
        abi: [
          {
            inputs: [
              { name: "tokenId", type: "uint256" },
              { name: "amount", type: "uint256" },
            ],
            name: "removeMargin",
            outputs: [],
            stateMutability: "nonpayable",
            type: "function",
          },
        ],
        functionName: "removeMargin",
        args: [BigInt(params.tokenId), amount],
      });

      console.log("✅ Margin removed from position! Transaction hash:", txHash);
      return { txHash, amount: params.amount };
    },
    onSuccess: () => {
      // Invalidate position queries to trigger refetch
      queryClient.invalidateQueries({
        queryKey: positionKeys.withBalance(address || ""),
        exact: true,
      });
      console.log("🔄 Position data invalidated after margin remove");
    },
  });
}

// Combined hook for all position operations
export function usePositionManagement() {
  const openPosition = useOpenPosition();
  const closePosition = useClosePosition();
  const addMargin = useAddMargin();
  const removeMargin = useRemoveMargin();
  const positionsData = usePositionsWithBalance();

  return {
    positions: positionsData.data?.positions || [],
    accountBalance: positionsData.data?.accountBalance,
    currentMarkPrice: positionsData.data?.currentMarkPrice,
    isLoading: positionsData.isLoading,
    error: positionsData.error,
    openPosition,
    closePosition,
    addMargin,
    removeMargin,
    refetch: positionsData.refetch,
  };
}
