// Core utilities and configurations
import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";
import { getContracts, UNICHAIN_SEPOLIA } from "./contracts-frontend";
import { createConfig, http } from "wagmi";
import { mainnet, polygon, optimism, arbitrum, base } from "wagmi/chains";
import { walletConnect, injected, coinbaseWallet } from "wagmi/connectors";
import { defineChain } from "viem";
import { formatUnits, parseUnits, encodeAbiParameters, keccak256 } from "viem";

// Utils
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

// Wagmi configuration
export const unichainSepolia = defineChain({
  id: 1301,
  name: "Unichain Sepolia",
  nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: {
      http: [
        process.env.NEXT_PUBLIC_UNICHAIN_SEPOLIA_RPC_URL ||
          "https://sepolia.unichain.org",
      ],
    },
    public: {
      http: [
        process.env.NEXT_PUBLIC_UNICHAIN_SEPOLIA_RPC_URL ||
          "https://sepolia.unichain.org",
      ],
    },
  },
  blockExplorers: {
    default: {
      name: "Unichain Sepolia Explorer",
      url: "https://sepolia.unichain.org",
    },
  },
  testnet: true,
});

export const wagmiConfig = createConfig({
  chains: [unichainSepolia, mainnet, polygon, optimism, arbitrum, base],
  connectors: [
    injected(),
    walletConnect({
      projectId:
        process.env.NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID || "YOUR_PROJECT_ID",
    }),
    coinbaseWallet({
      appName: "UNIPERP Trading",
    }),
  ],
  transports: {
    [unichainSepolia.id]: http(),
    [mainnet.id]: http(),
    [polygon.id]: http(),
    [optimism.id]: http(),
    [arbitrum.id]: http(),
    [base.id]: http(),
  },
  ssr: true,
});

// API client
const API_BASE_URL = process.env.NEXT_PUBLIC_API_URL || "/api";

export interface ApiResponse<T = any> {
  success: boolean;
  data: T;
  message: string;
}

export interface ApiError {
  error: string;
  status?: number;
}

class ApiClient {
  private baseURL: string;

  constructor(baseURL: string = API_BASE_URL) {
    this.baseURL = baseURL;
  }

  private async request<T>(
    endpoint: string,
    options: RequestInit = {}
  ): Promise<ApiResponse<T>> {
    const url = `${this.baseURL}${endpoint}`;

    const defaultHeaders = {
      "Content-Type": "application/json",
    };

    const config: RequestInit = {
      ...options,
      headers: {
        ...defaultHeaders,
        ...options.headers,
      },
    };

    try {
      const response = await fetch(url, config);

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({}));
        throw new Error(
          errorData.error || `HTTP error! status: ${response.status}`
        );
      }

      const data = await response.json();
      return data;
    } catch (error) {
      console.error(`API Error (${endpoint}):`, error);
      throw error;
    }
  }

  async get<T>(
    endpoint: string,
    params?: Record<string, string>
  ): Promise<ApiResponse<T>> {
    const url = new URL(endpoint, this.baseURL);
    if (params) {
      Object.entries(params).forEach(([key, value]) => {
        url.searchParams.append(key, value);
      });
    }

    return this.request<T>(url.pathname + url.search);
  }

  async post<T>(endpoint: string, data?: any): Promise<ApiResponse<T>> {
    return this.request<T>(endpoint, {
      method: "POST",
      body: data ? JSON.stringify(data) : undefined,
    });
  }

  async put<T>(endpoint: string, data?: any): Promise<ApiResponse<T>> {
    return this.request<T>(endpoint, {
      method: "PUT",
      body: data ? JSON.stringify(data) : undefined,
    });
  }

  async delete<T>(endpoint: string): Promise<ApiResponse<T>> {
    return this.request<T>(endpoint, {
      method: "DELETE",
    });
  }
}

export const apiClient = new ApiClient();
// Position utility functions
export function formatPositionSize(
  sizeBase: string,
  decimals: number = 18
): string {
  const size = parseFloat(sizeBase) / Math.pow(10, decimals);
  return Math.abs(size).toFixed(6);
}

export function formatPrice(price: string, decimals: number = 18): string {
  const priceValue = parseFloat(price) / Math.pow(10, decimals);
  return priceValue.toFixed(2);
}

export function formatMargin(margin: string, decimals: number = 6): string {
  const marginValue = parseFloat(margin) / Math.pow(10, decimals);
  return marginValue.toFixed(2);
}

export function calculateLeverage(
  size: number,
  margin: number,
  price: number
): number {
  if (margin === 0) return 0;
  const notionalValue = size * price;
  return notionalValue / margin;
}

export function calculatePositionValue(size: number, price: number): number {
  return size * price;
}

export function calculateRequiredMargin(
  size: number,
  price: number,
  leverage: number
): number {
  const notionalValue = size * price;
  return notionalValue / leverage;
}

export function calculatePnL(
  size: number,
  entryPrice: number,
  currentPrice: number,
  isLong: boolean
): number {
  const priceDiff = isLong
    ? currentPrice - entryPrice
    : entryPrice - currentPrice;
  return size * priceDiff;
}

export function calculatePnLPercentage(pnl: number, margin: number): number {
  if (margin === 0) return 0;
  return (pnl / margin) * 100;
}

export function isPositionLiquidatable(
  size: number,
  entryPrice: number,
  currentPrice: number,
  margin: number,
  isLong: boolean,
  liquidationThreshold: number = 0.1 // 10% threshold
): boolean {
  const pnl = calculatePnL(size, entryPrice, currentPrice, isLong);
  const remainingMargin = margin + pnl;
  const marginRatio = remainingMargin / margin;

  return marginRatio <= liquidationThreshold;
}

export function formatTimestamp(timestamp: string): string {
  const date = new Date(parseInt(timestamp) * 1000);
  return date.toLocaleTimeString([], {
    hour: "2-digit",
    minute: "2-digit",
  });
}

export function formatDate(timestamp: string): string {
  const date = new Date(parseInt(timestamp) * 1000);
  return date.toLocaleDateString();
}

export function getPositionSide(sizeBase: string): "long" | "short" {
  return parseFloat(sizeBase) > 0 ? "long" : "short";
}

export function getPositionSideDisplay(sizeBase: string): string {
  return getPositionSide(sizeBase) === "long" ? "Long" : "Short";
}

export function getPositionSideColor(sizeBase: string): string {
  return getPositionSide(sizeBase) === "long" ? "green" : "red";
}

// Risk management utilities
export function calculateMaxLeverage(
  margin: number,
  minMargin: number = 100, // $100 minimum
  maxLeverage: number = 20
): number {
  if (margin < minMargin) return 0;
  return Math.min(maxLeverage, margin / minMargin);
}

export function calculateMaxPositionSize(
  margin: number,
  price: number,
  maxLeverage: number = 20
): number {
  const maxNotionalValue = margin * maxLeverage;
  return maxNotionalValue / price;
}

export function validatePositionParams(
  size: number,
  margin: number,
  leverage: number,
  price: number,
  minMargin: number = 100,
  maxLeverage: number = 20
): { valid: boolean; error?: string } {
  if (margin < minMargin) {
    return { valid: false, error: `Minimum margin is ${minMargin} USDC` };
  }

  if (leverage > maxLeverage) {
    return { valid: false, error: `Maximum leverage is ${maxLeverage}x` };
  }

  // Calculate the actual position size based on margin and leverage
  const calculatedSize = (margin * leverage) / price;

  // Check if the calculated size matches the requested size (within 1% tolerance)
  const sizeDifference = Math.abs(calculatedSize - size) / size;
  if (sizeDifference > 0.01) {
    return {
      valid: false,
      error: `Size mismatch. Expected: ${calculatedSize.toFixed(
        4
      )}, Got: ${size.toFixed(4)}`,
    };
  }

  return { valid: true };
}

// Market utilities
export function getMarketSymbol(marketId: string): string {
  // In a real implementation, you'd map marketId to symbol
  // For now, return a default
  return "ETH/USDC";
}

export function getMarketIcon(marketId: string): string {
  // In a real implementation, you'd map marketId to icon
  // For now, return a default
  return "ETH";
}

// Pool and position calculation utilities
export function calculatePoolId(
  token0: string,
  token1: string,
  fee: number
): `0x${string}` {
  const encoded = encodeAbiParameters(
    [
      { name: "token0", type: "address" },
      { name: "token1", type: "address" },
      { name: "fee", type: "uint24" },
    ],
    [token0 as `0x${string}`, token1 as `0x${string}`, fee]
  );
  return keccak256(encoded);
}

export function calculatePositionSize(
  margin: number,
  leverage: number,
  price: number
): number {
  const notionalValue = margin * leverage;
  return notionalValue / price;
}

// Margin account types and utilities
export interface MarginBalance {
  userAddress: string;
  usdcWalletBalance: number;
  totalMarginAccountBalance: number;
  freeMargin: number;
  lockedMargin: number;
  availableForTrading: number;
  totalAccountValue: number;
  timestamp: string;
}

export interface MarginOperationResult {
  success: boolean;
  transactionHash: string;
  blockNumber: string;
  initialBalances: {
    usdcWalletBalance: number;
    totalMarginAccountBalance: number;
    freeMargin: number;
    lockedMargin: number;
  };
  updatedBalances: {
    usdcWalletBalance: number;
    totalMarginAccountBalance: number;
    freeMargin: number;
    lockedMargin: number;
  };
  balanceChanges: {
    usdcChange: number;
    totalMarginChange: number;
    freeMarginChange: number;
    lockedMarginChange: number;
  };
  timestamp: string;
}

// Contract utility functions
export function getMarginAccountContract(chainId: number = UNICHAIN_SEPOLIA) {
  const contracts = getContracts(chainId);
  return {
    address: contracts.marginAccount.address,
    abi: contracts.marginAccount.abi,
  };
}

export function getMockUSDCContract(chainId: number = UNICHAIN_SEPOLIA) {
  const contracts = getContracts(chainId);
  return {
    address: contracts.mockUSDC.address,
    abi: contracts.mockUSDC.abi,
  };
}

// Helper function to convert USDC amount to wei (6 decimals)
export function usdcToWei(amount: number): bigint {
  return parseUnits(amount.toString(), 6);
}

// Helper function to convert wei to USDC amount (6 decimals)
export function weiToUsdc(wei: bigint): number {
  return Number(formatUnits(wei, 6));
}

// Helper function to get current timestamp
export function getCurrentTimestamp(): string {
  return new Date().toISOString();
}

// Re-export contracts and constants
export { getContracts, UNICHAIN_SEPOLIA } from "./contracts-frontend";

// Portfolio event system
class PortfolioEventManager {
  private listeners: Set<() => void> = new Set();

  subscribe(callback: () => void) {
    this.listeners.add(callback);
    return () => this.listeners.delete(callback);
  }

  notify() {
    console.log("📢 Notifying portfolio listeners...");
    this.listeners.forEach((callback) => callback());
  }
}

export const portfolioEvents = new PortfolioEventManager();
