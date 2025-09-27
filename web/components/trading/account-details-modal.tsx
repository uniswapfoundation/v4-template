"use client";

import { useState, useRef } from "react";
import { useAccount, useDisconnect, useBalance, useReadContract } from "wagmi";
import { Address } from "viem";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Copy,
  ExternalLink,
  LogOut,
  ArrowUpRight,
  ArrowDownLeft,
  Wallet,
  X,
  RefreshCw,
  Loader2,
} from "lucide-react";
import { toast } from "sonner";
import { motion, AnimatePresence } from "framer-motion";
import {
  useMarginBalance,
  useDepositMargin,
  useWithdrawMargin,
  useTransactionConfirmation,
} from "@/hooks/api/use-margin";

interface AccountDetailsModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function AccountDetailsModal({
  open,
  onOpenChange,
}: AccountDetailsModalProps) {
  const { address, isConnected, chain } = useAccount();
  const { disconnect } = useDisconnect();
  const { data: balance } = useBalance({
    address: address,
  });

  // Remove local loading states since we'll use mutation states
  const [showDepositForm, setShowDepositForm] = useState(false);
  const [showWithdrawForm, setShowWithdrawForm] = useState(false);
  const [depositAmount, setDepositAmount] = useState("");
  const [withdrawAmount, setWithdrawAmount] = useState("");
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [isUpdating, setIsUpdating] = useState(false);

  // Frontend margin operations
  const {
    data: marginBalance,
    isLoading: marginBalanceLoading,
    refetch: refetchMarginBalance,
  } = useMarginBalance(address || "");
  const depositMarginMutation = useDepositMargin();
  const withdrawMarginMutation = useWithdrawMargin();
  const { waitForTransactionAndRefetch } = useTransactionConfirmation();

  // Get current USDC allowance for margin account
  const { data: usdcAllowance } = useReadContract({
    address: "0xb2feD1a40Fe6CA0be97Cde27e1D2dF1CC65Fd101", // MockUSDC address
    abi: [
      {
        inputs: [
          { name: "owner", type: "address" },
          { name: "spender", type: "address" },
        ],
        name: "allowance",
        outputs: [{ name: "", type: "uint256" }],
        stateMutability: "view",
        type: "function",
      },
    ],
    functionName: "allowance",
    args: [address as Address, "0x4Aa68070609C7EE42CDd7E431F202c0577c8556E"], // MarginAccount address
    query: {
      enabled: !!address,
    },
  });

  const copyAddress = () => {
    if (address) {
      navigator.clipboard.writeText(address);
      toast.success("Address copied to clipboard");
    }
  };

  const handleDisconnect = () => {
    disconnect();
    onOpenChange(false);
    toast.success("Wallet disconnected");
  };

  const handleDepositClick = () => {
    setShowWithdrawForm(false);
    setShowDepositForm(true);
  };

  const handleWithdrawClick = () => {
    setShowDepositForm(false);
    setShowWithdrawForm(true);
  };

  const handleDeposit = async () => {
    if (!depositAmount || Number.parseFloat(depositAmount) <= 0) {
      toast.error("Please enter a valid amount");
      return;
    }

    setIsUpdating(true);

    try {
      const result = await depositMarginMutation.mutateAsync(
        Number.parseFloat(depositAmount)
      );

      // Wait for transaction confirmation
      if (result.transactionHash) {
        toast.loading("Transaction submitted, waiting for confirmation...", {
          id: "confirm-deposit",
        });

        try {
          await waitForTransactionAndRefetch(result.transactionHash);

          toast.dismiss("confirm-deposit");
          toast.success("Deposit successful!");

          // Close form and reset
          setShowDepositForm(false);
          setDepositAmount("");

          // Stop loading immediately after transaction confirmation
          setIsUpdating(false);
        } catch (error) {
          console.error("Transaction confirmation failed:", error);
          const errorMessage =
            error instanceof Error
              ? error.message
              : "Transaction confirmation failed";
          setIsUpdating(false);
          toast.dismiss("confirm-deposit");
          toast.error(`Transaction failed: ${errorMessage}`);
        }
      }
    } catch (error) {
      console.error("Deposit error:", error);
      const errorMessage =
        error instanceof Error ? error.message : "Deposit failed";
      setIsUpdating(false);
      toast.error(`Deposit failed: ${errorMessage}`);
    }
  };

  const handleWithdraw = async () => {
    if (!withdrawAmount || Number.parseFloat(withdrawAmount) <= 0) {
      toast.error("Please enter a valid amount");
      return;
    }

    const maxAmount = marginBalance?.freeMargin || 0;
    if (Number.parseFloat(withdrawAmount) > maxAmount) {
      toast.error("Insufficient free margin");
      return;
    }

    setIsUpdating(true);

    try {
      const result = await withdrawMarginMutation.mutateAsync(
        Number.parseFloat(withdrawAmount)
      );

      // Wait for transaction confirmation
      if (result.transactionHash) {
        toast.loading("Withdrawal submitted, waiting for confirmation...", {
          id: "confirm-withdraw",
        });

        try {
          await waitForTransactionAndRefetch(result.transactionHash);

          toast.dismiss("confirm-withdraw");
          toast.success("Withdrawal successful!");

          // Close form and reset
          setShowWithdrawForm(false);
          setWithdrawAmount("");

          // Stop loading immediately after transaction confirmation
          setIsUpdating(false);
        } catch (error) {
          console.error("Transaction confirmation failed:", error);
          const errorMessage =
            error instanceof Error
              ? error.message
              : "Transaction confirmation failed";
          setIsUpdating(false);
          toast.dismiss("confirm-withdraw");
          toast.error(`Transaction failed: ${errorMessage}`);
        }
      }
    } catch (error) {
      console.error("Withdrawal error:", error);
      const errorMessage =
        error instanceof Error ? error.message : "Withdrawal failed";
      setIsUpdating(false);
      toast.error(`Withdrawal failed: ${errorMessage}`);
    }
  };

  const closeAllForms = () => {
    setShowDepositForm(false);
    setShowWithdrawForm(false);
    setTimeout(() => {
      setDepositAmount("");
      setWithdrawAmount("");
    }, 300);
  };

  const handleRetry = async () => {
    setIsRefreshing(true);
    try {
      await refetchMarginBalance();
    } catch (error) {
      toast.error("Failed to refresh balance");
    } finally {
      setTimeout(() => setIsRefreshing(false), 1000);
    }
  };

  if (!isConnected || !address) return null;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Wallet className="w-5 h-5" />
            Account Details
          </DialogTitle>
        </DialogHeader>

        <div className="space-y-6">
          {/* Network Info */}
          <div className="flex items-center justify-between">
            <span className="text-sm text-muted-foreground">Network</span>
            <Badge
              variant="secondary"
              className="bg-green-500/10 text-green-500 border-green-500/20"
            >
              <div className="w-2 h-2 bg-green-500 rounded-full mr-2" />
              {chain?.name || "Unknown"}
            </Badge>
          </div>

          <Separator />

          {/* Address */}
          <div className="space-y-2">
            <span className="text-sm text-muted-foreground">
              Wallet Address
            </span>
            <div className="flex items-center gap-2 p-3 bg-muted/50 rounded-lg">
              <code className="flex-1 text-sm font-mono">
                {address.slice(0, 6)}...{address.slice(-6)}
              </code>
              <Button
                size="sm"
                variant="ghost"
                onClick={copyAddress}
                className="h-8 w-8 p-0"
              >
                <Copy className="w-4 h-4" />
              </Button>
              <Button
                size="sm"
                variant="ghost"
                onClick={() =>
                  window.open(
                    `https://etherscan.io/address/${address}`,
                    "_blank"
                  )
                }
                className="h-8 w-8 p-0"
              >
                <ExternalLink className="w-4 h-4" />
              </Button>
            </div>
          </div>

          {/* Margin Account Balance - Combined Card */}
          {marginBalance && (
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-sm text-muted-foreground">
                  Margin Account
                </span>
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={handleRetry}
                  disabled={isRefreshing || marginBalanceLoading || isUpdating}
                  className="h-6 w-6 p-0 hover:bg-blue-500/10 disabled:opacity-50"
                >
                  <RefreshCw
                    className={`w-3 h-3 ${
                      isRefreshing ||
                      marginBalanceLoading ||
                      isUpdating ||
                      depositMarginMutation.isPending ||
                      withdrawMarginMutation.isPending
                        ? "animate-spin"
                        : ""
                    }`}
                  />
                </Button>
              </div>
              <div className="p-4 bg-[oklab(0.2393_0_0_/_0.5)] rounded-lg">
                {/* Total Balance - Prominent */}
                <div className="text-center mb-4">
                  <div className="text-muted-foreground text-sm mb-1">
                    Total Balance
                  </div>
                  <div
                    className={`text-3xl font-bold text-blue-600 ${
                      isRefreshing ||
                      marginBalanceLoading ||
                      isUpdating ||
                      depositMarginMutation.isPending ||
                      withdrawMarginMutation.isPending
                        ? "animate-pulse"
                        : ""
                    }`}
                  >
                    {marginBalance.totalMarginAccountBalance.toFixed(2)} USDC
                  </div>
                </div>

                {/* Divider */}
                <div className="border-t border-muted/50 mb-4"></div>

                {/* Free and Locked Margins */}
                <div className="grid grid-cols-2 gap-4 text-sm">
                  <div className="text-center">
                    <div className="text-muted-foreground mb-1">
                      Free Margin
                    </div>
                    <div
                      className={`font-semibold text-green-500 ${
                        isRefreshing ||
                        marginBalanceLoading ||
                        isUpdating ||
                        depositMarginMutation.isPending ||
                        withdrawMarginMutation.isPending
                          ? "animate-pulse"
                          : ""
                      }`}
                    >
                      {marginBalance.freeMargin.toFixed(2)} USDC
                    </div>
                  </div>
                  <div className="text-center">
                    <div className="text-muted-foreground mb-1">
                      Locked Margin
                    </div>
                    <div
                      className={`font-semibold text-orange-500 ${
                        isRefreshing ||
                        marginBalanceLoading ||
                        isUpdating ||
                        depositMarginMutation.isPending ||
                        withdrawMarginMutation.isPending
                          ? "animate-pulse"
                          : ""
                      }`}
                    >
                      {marginBalance.lockedMargin.toFixed(2)} USDC
                    </div>
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* Loading state for margin balance */}
          {marginBalanceLoading && (
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-sm text-muted-foreground">
                  Margin Account
                </span>
                <div className="flex items-center gap-2">
                  <Loader2 className="w-3 h-3 animate-spin text-blue-500" />
                  <span className="text-xs text-muted-foreground">
                    Loading...
                  </span>
                </div>
              </div>
              <div className="p-4 bg-gradient-to-br from-blue-500/5 to-blue-600/5 border border-blue-500/20 rounded-lg">
                <div className="text-center mb-4">
                  <div className="text-muted-foreground text-sm mb-1">
                    Total Balance
                  </div>
                  <div className="flex items-center justify-center gap-2">
                    <div className="h-8 w-32 bg-gradient-to-r from-blue-500/20 via-blue-500/30 to-blue-500/20 rounded bg-[length:200%_100%] animate-[shimmer_2s_ease-in-out_infinite]"></div>
                    <Loader2 className="w-4 h-4 animate-spin text-blue-500" />
                  </div>
                </div>

                {/* Divider */}
                <div className="border-t border-muted/30 mb-4"></div>

                <div className="grid grid-cols-2 gap-4 text-sm">
                  <div className="text-center">
                    <div className="text-muted-foreground mb-1">
                      Free Margin
                    </div>
                    <div className="flex items-center justify-center gap-1">
                      <div className="h-5 w-20 bg-gradient-to-r from-green-500/20 via-green-500/30 to-green-500/20 rounded bg-[length:200%_100%] animate-[shimmer_2s_ease-in-out_infinite]"></div>
                      <Loader2 className="w-3 h-3 animate-spin text-green-500" />
                    </div>
                  </div>
                  <div className="text-center">
                    <div className="text-muted-foreground mb-1">
                      Locked Margin
                    </div>
                    <div className="flex items-center justify-center gap-1">
                      <div className="h-5 w-20 bg-gradient-to-r from-orange-500/20 via-orange-500/30 to-orange-500/20 rounded bg-[length:200%_100%] animate-[shimmer_2s_ease-in-out_infinite]"></div>
                      <Loader2 className="w-3 h-3 animate-spin text-orange-500" />
                    </div>
                  </div>
                </div>
              </div>
            </div>
          )}

          <Separator />

          {/* Action Buttons */}
          <div className="grid grid-cols-2 gap-3">
            <Button
              onClick={handleDepositClick}
              disabled={isUpdating || marginBalanceLoading}
              className="bg-green-600 hover:bg-green-700 text-white disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {isUpdating ? (
                <Loader2 className="w-4 h-4 mr-2 animate-spin" />
              ) : (
                <ArrowDownLeft className="w-4 h-4 mr-2" />
              )}
              Deposit
            </Button>
            <Button
              onClick={handleWithdrawClick}
              disabled={isUpdating || marginBalanceLoading}
              variant="outline"
              className="border-orange-500/20 text-orange-500 hover:bg-orange-500/10 bg-transparent disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {isUpdating ? (
                <Loader2 className="w-4 h-4 mr-2 animate-spin" />
              ) : (
                <ArrowUpRight className="w-4 h-4 mr-2" />
              )}
              Withdraw
            </Button>
          </div>

          {/* Animated Forms Container */}
          <motion.div
            layout
            transition={{
              duration: 0.3,
              ease: [0.16, 1, 0.3, 1],
              when: "beforeChildren",
            }}
          >
            <AnimatePresence mode="wait">
              {(showDepositForm || showWithdrawForm) && (
                <motion.div
                  layout
                  initial={{
                    opacity: 0,
                    scale: 0.98,
                    height: 0,
                    marginTop: 0,
                    paddingTop: 0,
                    paddingBottom: 0,
                  }}
                  animate={{
                    opacity: 1,
                    scale: 1,
                    height: "auto",
                    marginTop: 24,
                    paddingTop: 16,
                    paddingBottom: 16,
                  }}
                  exit={{
                    opacity: 0,
                    scale: 0.98,
                    height: 0,
                    marginTop: 0,
                    paddingTop: 0,
                    paddingBottom: 0,
                  }}
                  transition={{
                    duration: 0.3,
                    ease: [0.16, 1, 0.3, 1],
                    layout: {
                      duration: 0.3,
                      ease: [0.16, 1, 0.3, 1],
                    },
                  }}
                  className={`rounded-lg border-2 overflow-hidden transition-colors duration-300 ${
                    showDepositForm
                      ? "bg-green-500/5 border-green-500/20"
                      : "bg-orange-500/5 border-orange-500/20"
                  }`}
                >
                  <div className="px-4">
                    <div className="flex items-center justify-between mb-4">
                      <motion.div
                        className="flex items-center gap-2"
                        key={
                          showDepositForm ? "deposit-header" : "withdraw-header"
                        }
                        initial={{ opacity: 0, x: -10 }}
                        animate={{ opacity: 1, x: 0 }}
                        exit={{ opacity: 0, x: 10 }}
                        transition={{ duration: 0.2 }}
                      >
                        {showDepositForm ? (
                          <>
                            <ArrowDownLeft className="w-5 h-5 text-green-500" />
                            <div>
                              <h3 className="font-semibold text-green-500">
                                Deposit Funds
                              </h3>
                            </div>
                          </>
                        ) : (
                          <>
                            <ArrowUpRight className="w-5 h-5 text-orange-500" />
                            <div>
                              <h3 className="font-semibold text-orange-500">
                                Withdraw Funds
                              </h3>
                            </div>
                          </>
                        )}
                      </motion.div>
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={closeAllForms}
                        className="h-6 w-6 p-0 hover:bg-black/10"
                      >
                        <X className="w-4 h-4" />
                      </Button>
                    </div>

                    <div className="space-y-4">
                      <div className="space-y-2">
                        <Label htmlFor="amount" className="text-sm">
                          Amount (USDC)
                        </Label>
                        <div className="relative">
                          <Input
                            id="amount"
                            type="number"
                            placeholder="0.00"
                            value={
                              showDepositForm ? depositAmount : withdrawAmount
                            }
                            onChange={(e) => {
                              if (showDepositForm) {
                                setDepositAmount(e.target.value);
                              } else {
                                setWithdrawAmount(e.target.value);
                              }
                            }}
                            className="pr-16 font-mono [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none [-moz-appearance:textfield]"
                            step="0.0001"
                            min="0"
                          />
                          <div className="absolute right-3 top-1/2 -translate-y-1/2 text-sm text-muted-foreground">
                            USDC
                          </div>
                        </div>

                        <AnimatePresence mode="wait">
                          {showWithdrawForm && marginBalance && (
                            <motion.div
                              initial={{ opacity: 0, height: 0 }}
                              animate={{ opacity: 1, height: "auto" }}
                              exit={{ opacity: 0, height: 0 }}
                              transition={{ duration: 0.2 }}
                              className="flex justify-between text-xs text-muted-foreground overflow-hidden"
                            >
                              <span>
                                Available: {marginBalance.freeMargin.toFixed(2)}{" "}
                                USDC
                              </span>
                              <Button
                                size="sm"
                                variant="ghost"
                                onClick={() =>
                                  setWithdrawAmount(
                                    marginBalance.freeMargin.toString()
                                  )
                                }
                                className="h-auto p-0 text-xs text-orange-500 hover:text-orange-600"
                              >
                                Max
                              </Button>
                            </motion.div>
                          )}
                        </AnimatePresence>
                      </div>

                      <motion.div
                        key={
                          showDepositForm ? "deposit-button" : "withdraw-button"
                        }
                        initial={{ opacity: 0, y: 10 }}
                        animate={{ opacity: 1, y: 0 }}
                        transition={{ duration: 0.2, delay: 0.1 }}
                      >
                        <Button
                          onClick={
                            showDepositForm ? handleDeposit : handleWithdraw
                          }
                          disabled={
                            showDepositForm
                              ? depositMarginMutation.isPending || isUpdating
                              : withdrawMarginMutation.isPending || isUpdating
                          }
                          className={`w-full transition-all duration-300 ${
                            showDepositForm
                              ? "bg-green-600 hover:bg-green-700 text-white disabled:opacity-50 disabled:cursor-not-allowed"
                              : "bg-orange-600 hover:bg-orange-700 text-white disabled:opacity-50 disabled:cursor-not-allowed"
                          }`}
                        >
                          <div className="flex items-center justify-center gap-2">
                            {(showDepositForm
                              ? depositMarginMutation.isPending
                              : withdrawMarginMutation.isPending) && (
                              <Loader2 className="w-4 h-4 animate-spin" />
                            )}
                            {showDepositForm
                              ? depositMarginMutation.isPending
                                ? "Processing Deposit..."
                                : "Confirm Deposit"
                              : withdrawMarginMutation.isPending
                              ? "Processing Withdrawal..."
                              : "Confirm Withdrawal"}
                          </div>
                        </Button>
                      </motion.div>
                    </div>
                  </div>
                </motion.div>
              )}
            </AnimatePresence>
          </motion.div>

          <Separator />

          {/* Disconnect Button */}
          <Button
            onClick={handleDisconnect}
            variant="outline"
            className="w-full border-red-500/20 text-red-500 hover:bg-red-500/10 bg-transparent"
          >
            <LogOut className="w-4 h-4 mr-2" />
            Disconnect Wallet
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
