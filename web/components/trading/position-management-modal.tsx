"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { cn } from "@/lib/core";
import { Position } from "@/hooks/api/use-positions";
import { usePortfolioRefresh } from "@/hooks/use-portfolio-refresh";
import { toast } from "sonner";
import { usePositionManagement } from "@/hooks/api/use-positions";
import { motion, AnimatePresence } from "framer-motion";

interface PositionManagementModalProps {
  position: Position | null;
  isOpen: boolean;
  onClose: () => void;
}

export function PositionManagementModal({
  position,
  isOpen,
  onClose,
}: PositionManagementModalProps) {
  const [activeTab, setActiveTab] = useState<"close" | "add-margin">(
    "add-margin"
  );
  const [closePercentage, setClosePercentage] = useState("100");
  const [marginAmount, setMarginAmount] = useState("");
  const [isLoading, setIsLoading] = useState(false);

  const { refreshPortfolio } = usePortfolioRefresh();
  const { closePosition, addMargin } = usePositionManagement();

  if (!position) return null;

  const handleClosePosition = async () => {
    if (!position) return;

    setIsLoading(true);
    try {
      const percentage = parseInt(closePercentage);
      if (percentage <= 0 || percentage > 100) {
        throw new Error("Close percentage must be between 1 and 100");
      }

      await closePosition.mutateAsync({
        tokenId: position.tokenId,
        percentage,
      });

      toast.success(
        `Successfully closed ${percentage}% of position #${position.tokenId}`
      );

      await refreshPortfolio();
      onClose();
    } catch (error) {
      console.error("Error closing position:", error);
      toast.error(
        error instanceof Error ? error.message : "Failed to close position"
      );
    } finally {
      setIsLoading(false);
    }
  };

  const handleAddMargin = async () => {
    if (!position || !marginAmount) return;

    setIsLoading(true);
    try {
      const amount = parseFloat(marginAmount);
      if (amount <= 0) {
        throw new Error("Margin amount must be greater than 0");
      }

      await addMargin.mutateAsync({
        tokenId: position.tokenId,
        amount,
      });

      toast.success(
        `Successfully added ${amount} USDC margin to position #${position.tokenId}`
      );

      await refreshPortfolio();
      setMarginAmount("");
    } catch (error) {
      console.error("Error adding margin:", error);
      toast.error(
        error instanceof Error ? error.message : "Failed to add margin"
      );
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <AnimatePresence>
        {isOpen && (
          <DialogContent className="sm:max-w-lg">
            <motion.div
              initial={{ opacity: 0, scale: 0.95, y: 20 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.95, y: 20 }}
              transition={{
                duration: 0.2,
                ease: [0.16, 1, 0.3, 1],
              }}
            >
              <DialogHeader className="space-y-3">
                <DialogTitle className="flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <div className="w-8 h-8 bg-primary/10 rounded-full flex items-center justify-center">
                      <span className="text-sm font-bold text-primary">
                        #{position.tokenId}
                      </span>
                    </div>
                    <div>
                      <div className="text-lg font-semibold">
                        Manage Position
                      </div>
                      <div className="flex items-center gap-2">
                        <span className="text-sm text-muted-foreground">
                          ETH/USDC
                        </span>
                        <Badge
                          variant="outline"
                          className={cn(
                            "text-xs font-medium px-2 py-1",
                            position.isLong
                              ? "text-green-700 bg-green-100 border-green-200"
                              : "text-red-700 bg-red-100 border-red-200"
                          )}
                        >
                          {position.isLong ? "LONG" : "SHORT"}
                        </Badge>
                      </div>
                    </div>
                  </div>
                </DialogTitle>
                <div className="grid grid-cols-3 gap-4 p-4 bg-muted/30 rounded-lg">
                  <div className="text-center">
                    <div className="text-sm text-muted-foreground">Size</div>
                    <div className="font-mono font-semibold">
                      {position.sizeBase.toFixed(4)} VETH
                    </div>
                  </div>
                  <div className="text-center">
                    <div className="text-sm text-muted-foreground">
                      Leverage
                    </div>
                    <div className="font-mono font-semibold">
                      {position.leverage.toFixed(2)}x
                    </div>
                  </div>
                  <div className="text-center">
                    <div className="text-sm text-muted-foreground">Margin</div>
                    <div className="font-mono font-semibold">
                      {position.margin.toFixed(2)} USDC
                    </div>
                  </div>
                </div>
              </DialogHeader>

              <div className="relative p-1 bg-muted rounded-lg">
                {/* Animated slider background */}
                <motion.div
                  className={cn(
                    "absolute top-1 bottom-1 w-[calc(50%-2px)] rounded-md",
                    activeTab === "add-margin"
                      ? "bg-green-600"
                      : "bg-destructive"
                  )}
                  initial={false}
                  animate={{
                    x: activeTab === "add-margin" ? 0 : "calc(100% + 4px)",
                  }}
                  transition={{
                    type: "spring",
                    stiffness: 300,
                    damping: 30,
                  }}
                />

                {/* Toggle buttons */}
                <div className="relative grid grid-cols-2 gap-1">
                  {(["add-margin", "close"] as const).map((tab) => (
                    <button
                      key={tab}
                      onClick={() => setActiveTab(tab)}
                      className={cn(
                        "relative z-10 py-2 px-4 text-xs font-medium rounded-md transition-colors duration-200",
                        activeTab === tab
                          ? "text-white"
                          : "text-muted-foreground hover:text-foreground"
                      )}
                    >
                      {tab === "close" ? "Close Position" : "Add Margin"}
                    </button>
                  ))}
                </div>
              </div>

              <motion.div
                layout
                transition={{
                  duration: 0.3,
                  ease: [0.16, 1, 0.3, 1],
                  when: "beforeChildren",
                }}
              >
                <AnimatePresence mode="wait">
                  {activeTab === "close" && (
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
                      className="rounded-lg overflow-hidden transition-colors duration-300 bg-[oklab(0.2393_0_0_/_0.5)]"
                    >
                      <div className="px-4">
                        <div className="space-y-4">
                          <div className="space-y-3">
                            <Label
                              htmlFor="close-percentage"
                              className="text-sm font-medium"
                            >
                              Close Percentage
                            </Label>
                            <div className="flex gap-3">
                              <Input
                                id="close-percentage"
                                type="number"
                                min="1"
                                max="100"
                                value={closePercentage}
                                onChange={(e) =>
                                  setClosePercentage(e.target.value)
                                }
                                placeholder="100"
                                className="text-center font-mono [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none [-moz-appearance:textfield]"
                              />
                              <span className="text-sm text-muted-foreground self-center font-medium">
                                %
                              </span>
                            </div>
                            <div className="flex gap-2">
                              {[25, 50, 75, 100].map((percent) => (
                                <Button
                                  key={percent}
                                  variant="outline"
                                  size="sm"
                                  onClick={() =>
                                    setClosePercentage(percent.toString())
                                  }
                                  className={cn(
                                    "text-xs",
                                    closePercentage === percent.toString() &&
                                      "bg-primary text-primary-foreground"
                                  )}
                                >
                                  {percent}%
                                </Button>
                              ))}
                            </div>
                            <p className="text-sm text-muted-foreground">
                              {closePercentage === "100" ? (
                                <>
                                  <span className="font-semibold">
                                    Fully closing
                                  </span>{" "}
                                  your position (
                                  <span className="font-mono">
                                    {position.sizeBase} VETH
                                  </span>
                                  )
                                </>
                              ) : (
                                <>
                                  <span className="font-semibold">
                                    Partially closing
                                  </span>{" "}
                                  {closePercentage}% of your position (
                                  <span className="font-mono">
                                    {position.sizeBase *
                                      (parseInt(closePercentage) / 100)}{" "}
                                    VETH
                                  </span>
                                  ) - This effectively removes margin
                                </>
                              )}
                            </p>
                          </div>

                          <div className="bg-muted/30 p-4 rounded-lg space-y-3 border">
                            <div className="flex justify-between items-center">
                              <span className="text-sm text-muted-foreground">
                                Current Margin:
                              </span>
                              <span className="font-mono font-semibold">
                                {position.margin.toFixed(2)} USDC
                              </span>
                            </div>
                            <div className="flex justify-between items-center">
                              <span className="text-sm text-muted-foreground">
                                Current PnL:
                              </span>
                              <span
                                className={cn(
                                  "font-mono font-semibold",
                                  position.unrealizedPnL >= 0
                                    ? "text-green-600"
                                    : "text-red-600"
                                )}
                              >
                                {position.unrealizedPnL >= 0 ? "+" : ""}
                                {position.unrealizedPnL.toFixed(2)} USDC
                              </span>
                            </div>
                            <div className="flex justify-between items-center">
                              <span className="text-sm text-muted-foreground">
                                Entry Price:
                              </span>
                              <span className="font-mono font-semibold">
                                {position.entryPrice.toFixed(2)} USDC
                              </span>
                            </div>
                          </div>
                        </div>

                        <Button
                          onClick={handleClosePosition}
                          disabled={isLoading || closePosition.isPending}
                          className="w-full h-12 text-base font-semibold mt-4 flex items-center justify-center"
                          variant="destructive"
                        >
                          {isLoading || closePosition.isPending ? (
                            <div className="flex items-center justify-center gap-2">
                              <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
                              {closePercentage === "100"
                                ? "Closing Position..."
                                : "Partially Closing..."}
                            </div>
                          ) : closePercentage === "100" ? (
                            "Close Position"
                          ) : (
                            `Close ${closePercentage}% (Remove Margin)`
                          )}
                        </Button>
                      </div>
                    </motion.div>
                  )}

                  {activeTab === "add-margin" && (
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
                      className="rounded-lg overflow-hidden transition-colors duration-300 bg-[oklab(0.2393_0_0_/_0.5)]"
                    >
                      <div className="px-4">
                        <div className="space-y-4">
                          <div className="space-y-3">
                            <Label
                              htmlFor="add-margin-amount"
                              className="text-sm font-medium"
                            >
                              Amount to Add
                            </Label>
                            <div className="flex gap-3">
                              <Input
                                id="add-margin-amount"
                                type="number"
                                min="0.01"
                                step="0.01"
                                value={marginAmount}
                                onChange={(e) =>
                                  setMarginAmount(e.target.value)
                                }
                                placeholder="0.00"
                                className="text-center font-mono [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none [-moz-appearance:textfield]"
                              />
                            </div>
                            <div className="flex gap-2">
                              {[50, 100, 200, 500].map((amount) => (
                                <Button
                                  key={amount}
                                  variant="outline"
                                  size="sm"
                                  onClick={() =>
                                    setMarginAmount(amount.toString())
                                  }
                                  className={cn(
                                    "text-xs",
                                    marginAmount === amount.toString() &&
                                      "bg-primary text-primary-foreground"
                                  )}
                                >
                                  {amount}
                                </Button>
                              ))}
                            </div>
                          </div>

                          <div className="bg-muted/30 p-4 rounded-lg space-y-3 border">
                            <div className="flex justify-between items-center">
                              <span className="text-sm text-muted-foreground">
                                Current Margin:
                              </span>
                              <span className="font-mono font-semibold">
                                {position.margin.toFixed(2)} USDC
                              </span>
                            </div>
                            <div className="flex justify-between items-center">
                              <span className="text-sm text-muted-foreground">
                                Adding:
                              </span>
                              <span className="font-mono font-semibold text-blue-600">
                                +{(parseFloat(marginAmount) || 0).toFixed(2)}{" "}
                                USDC
                              </span>
                            </div>
                            <div className="border-t pt-3">
                              <div className="flex justify-between items-center">
                                <span className="text-sm font-medium">
                                  New Margin:
                                </span>
                                <span className="font-mono font-bold text-green-600">
                                  {(
                                    position.margin +
                                    (parseFloat(marginAmount) || 0)
                                  ).toFixed(2)}{" "}
                                  USDC
                                </span>
                              </div>
                            </div>
                          </div>
                        </div>

                        <Button
                          onClick={handleAddMargin}
                          disabled={
                            isLoading || addMargin.isPending || !marginAmount
                          }
                          className="w-full h-12 text-base font-semibold mt-4 bg-green-600 hover:bg-green-700 text-white"
                        >
                          {isLoading || addMargin.isPending ? (
                            <div className="flex items-center gap-2">
                              <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
                              Adding Margin...
                            </div>
                          ) : (
                            `Add ${marginAmount || "0"} USDC Margin`
                          )}
                        </Button>
                      </div>
                    </motion.div>
                  )}
                </AnimatePresence>
              </motion.div>
            </motion.div>
          </DialogContent>
        )}
      </AnimatePresence>
    </Dialog>
  );
}
