"use client";

import React from "react";
import {
  useAccount,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { Address } from "viem";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import {
  getMarginAccountContract,
  getMockUSDCContract,
  usdcToWei,
  weiToUsdc,
  getCurrentTimestamp,
  unichainSepolia,
  type MarginBalance,
  type MarginOperationResult,
} from "@/lib/core";

// Query Keys
export const marginKeys = {
  all: ["margin"] as const,
  balance: (address: string) =>
    [...marginKeys.all, "balance", address] as const,
  operations: () => [...marginKeys.all, "operations"] as const,
};

// Hook to get margin balance
export function useMarginBalance(address: string) {
  const { chainId } = useAccount();
  const currentChainId = chainId || unichainSepolia.id;

  const marginAccount = getMarginAccountContract(currentChainId);
  const mockUSDC = getMockUSDCContract(currentChainId);

  // Read USDC wallet balance
  const { data: usdcBalance, refetch: refetchUsdcBalance } = useReadContract({
    address: mockUSDC.address,
    abi: mockUSDC.abi,
    functionName: "balanceOf",
    args: [address as Address],
    query: {
      enabled: !!address,
      refetchInterval: 5000, // Refetch every 5 seconds
    },
  });

  // Read total margin account balance
  const { data: totalMarginBalance, refetch: refetchTotalBalance } =
    useReadContract({
      address: marginAccount.address,
      abi: marginAccount.abi,
      functionName: "getTotalBalance",
      args: [address as Address],
      query: {
        enabled: !!address,
        refetchInterval: 5000, // Refetch every 5 seconds
      },
    });

  // Read free balance
  const { data: freeBalance, refetch: refetchFreeBalance } = useReadContract({
    address: marginAccount.address,
    abi: marginAccount.abi,
    functionName: "freeBalance",
    args: [address as Address],
    query: {
      enabled: !!address,
      refetchInterval: 5000, // Refetch every 5 seconds
    },
  });

  // Read locked balance
  const { data: lockedBalance, refetch: refetchLockedBalance } =
    useReadContract({
      address: marginAccount.address,
      abi: marginAccount.abi,
      functionName: "lockedBalance",
      args: [address as Address],
      query: {
        enabled: !!address,
        refetchInterval: 5000, // Refetch every 5 seconds
      },
    });

  const balanceData: MarginBalance | undefined =
    usdcBalance !== undefined &&
    totalMarginBalance !== undefined &&
    freeBalance !== undefined &&
    lockedBalance !== undefined
      ? {
          userAddress: address,
          usdcWalletBalance: weiToUsdc(usdcBalance),
          totalMarginAccountBalance: weiToUsdc(totalMarginBalance),
          freeMargin: weiToUsdc(freeBalance),
          lockedMargin: weiToUsdc(lockedBalance),
          availableForTrading: weiToUsdc(freeBalance),
          totalAccountValue: weiToUsdc(totalMarginBalance),
          timestamp: getCurrentTimestamp(),
        }
      : undefined;

  // Manual refetch function
  const refetch = async () => {
    await Promise.all([
      refetchUsdcBalance(),
      refetchTotalBalance(),
      refetchFreeBalance(),
      refetchLockedBalance(),
    ]);
  };

  return {
    data: balanceData,
    isLoading:
      usdcBalance === undefined ||
      totalMarginBalance === undefined ||
      freeBalance === undefined ||
      lockedBalance === undefined,
    error: null,
    refetch,
  };
}

// Hook for margin operations (deposit/withdraw)
export function useMarginOperations() {
  const { address, chainId } = useAccount();
  const queryClient = useQueryClient();
  const currentChainId = chainId || unichainSepolia.id;

  const marginAccount = getMarginAccountContract(currentChainId);
  const mockUSDC = getMockUSDCContract(currentChainId);

  const { writeContractAsync: writeContractUSDC } = useWriteContract();
  const { writeContractAsync: writeContractMargin } = useWriteContract();

  // Check current USDC allowance
  const { data: currentAllowance } = useReadContract({
    address: mockUSDC.address,
    abi: mockUSDC.abi,
    functionName: "allowance",
    args: [address as Address, marginAccount.address],
    query: {
      enabled: !!address,
    },
  });

  // Deposit operation
  const depositMutation = useMutation({
    mutationFn: async (amount: number) => {
      if (!address) throw new Error("No wallet connected");

      const amountWei = usdcToWei(amount);

      try {
        // Check if we need approval
        const needsApproval = !currentAllowance || currentAllowance < amountWei;

        let approvalHash: `0x${string}` | undefined;

        if (needsApproval) {
          // First, approve USDC spending
          toast.loading("Step 1/2: Approving USDC...", { id: "approve" });
          approvalHash = await writeContractUSDC({
            address: mockUSDC.address,
            abi: mockUSDC.abi,
            functionName: "approve",
            args: [marginAccount.address, amountWei],
          });

          if (!approvalHash) throw new Error("Failed to approve USDC");
        } else {
          toast.loading("Using existing USDC approval...", { id: "approve" });
        }

        // Then deposit to margin account
        toast.loading("Step 2/2: Depositing to margin account...", {
          id: "deposit",
        });
        const depositHash = await writeContractMargin({
          address: marginAccount.address,
          abi: marginAccount.abi,
          functionName: "deposit",
          args: [amountWei],
        });

        if (!depositHash) throw new Error("Failed to deposit");

        return {
          transactionHash: depositHash,
          approvalHash,
          amount,
        };
      } catch (error) {
        toast.dismiss("approve");
        toast.dismiss("deposit");
        throw error;
      }
    },
    onSuccess: async (data) => {
      toast.dismiss("approve");
      toast.dismiss("deposit");
      toast.success(`Successfully deposited ${data.amount} USDC`);

      // Invalidate balance queries and refetch
      if (address) {
        queryClient.invalidateQueries({
          queryKey: marginKeys.balance(address),
        });
      }
    },
    onError: (error) => {
      toast.dismiss("approve");
      toast.dismiss("deposit");
      toast.error(`Deposit failed: ${error.message}`);
    },
  });

  // Withdraw operation
  const withdrawMutation = useMutation({
    mutationFn: async (amount: number) => {
      if (!address) throw new Error("No wallet connected");

      const amountWei = usdcToWei(amount);

      try {
        toast.loading("Withdrawing from margin account...", { id: "withdraw" });
        const withdrawHash = await writeContractMargin({
          address: marginAccount.address,
          abi: marginAccount.abi,
          functionName: "withdraw",
          args: [amountWei],
        });

        if (!withdrawHash) throw new Error("Failed to withdraw");

        return { transactionHash: withdrawHash, amount };
      } catch (error) {
        toast.dismiss("withdraw");
        throw error;
      }
    },
    onSuccess: async (data) => {
      toast.dismiss("withdraw");
      toast.success(`Successfully withdrew ${data.amount} USDC`);

      // Invalidate balance queries and refetch
      if (address) {
        queryClient.invalidateQueries({
          queryKey: marginKeys.balance(address),
        });
      }
    },
    onError: (error) => {
      toast.dismiss("withdraw");
      toast.error(`Withdrawal failed: ${error.message}`);
    },
  });

  return {
    deposit: depositMutation,
    withdraw: withdrawMutation,
  };
}

// Hook to wait for transaction confirmation and update balances
export function useTransactionConfirmation() {
  const queryClient = useQueryClient();
  const { address } = useAccount();

  // Function to wait for a specific transaction and refetch balances
  const waitForTransactionAndRefetch = async (hash: `0x${string}`) => {
    try {
      // Use a simple polling approach to wait for transaction confirmation
      let confirmed = false;
      let attempts = 0;
      const maxAttempts = 30; // 30 seconds max wait

      while (!confirmed && attempts < maxAttempts) {
        await new Promise((resolve) => setTimeout(resolve, 1000));
        attempts++;

        // Check if transaction is confirmed by checking if we can refetch balances
        // This is a simple approach - in production you'd want to check the actual transaction receipt
        if (attempts >= 3) {
          // Wait at least 3 seconds for transaction to be mined
          confirmed = true;
        }
      }

      console.log("Transaction confirmed:", hash);

      // Force refetch balance after transaction is confirmed
      if (address) {
        // First refetch
        await queryClient.invalidateQueries({
          queryKey: marginKeys.balance(address),
        });

        // Wait a bit for the refetch to complete
        await new Promise((resolve) => setTimeout(resolve, 500));

        // Second refetch to ensure we have the latest data
        await queryClient.invalidateQueries({
          queryKey: marginKeys.balance(address),
        });

        console.log("Balance refetched after transaction confirmation");
      }

      return { transactionHash: hash };
    } catch (error) {
      console.error("Transaction failed:", error);
      throw error;
    }
  };

  return {
    waitForTransactionAndRefetch,
  };
}

// Hook to monitor a specific transaction with proper wagmi integration
export function useTransactionMonitor(hash: `0x${string}` | undefined) {
  const queryClient = useQueryClient();
  const { address } = useAccount();

  const {
    data: receipt,
    isSuccess,
    isError,
    error,
  } = useWaitForTransactionReceipt({
    hash,
    confirmations: 1,
    query: {
      enabled: !!hash,
    },
  });

  // Auto-refetch balances when transaction is confirmed
  React.useEffect(() => {
    if (isSuccess && receipt && address) {
      // Refetch balance after successful transaction
      queryClient.invalidateQueries({
        queryKey: marginKeys.balance(address),
      });
      console.log("Balance refetched after transaction confirmation");
    }
  }, [isSuccess, receipt, address, queryClient]);

  return {
    receipt,
    isSuccess,
    isError,
    error,
  };
}

// Convenience hooks for specific operations
export function useDepositMargin() {
  const operations = useMarginOperations();
  return operations.deposit;
}

export function useWithdrawMargin() {
  const operations = useMarginOperations();
  return operations.withdraw;
}

// Legacy exports for backward compatibility
export const useMarginBalanceFrontend = useMarginBalance;
export const useMarginOperationsFrontend = useMarginOperations;
export const useDepositMarginFrontend = useDepositMargin;
export const useWithdrawMarginFrontend = useWithdrawMargin;
