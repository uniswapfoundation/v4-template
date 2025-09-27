"use client";

import { useState } from "react";
import { useAccount } from "wagmi";
import { Button } from "@/components/ui/button";
import { ChevronDown, Wallet } from "lucide-react";
import { WalletSelectionModal } from "./wallet-selection-modal";
import { AccountDetailsModal } from "./account-details-modal";

export function WalletConnectButton() {
  const [showWalletModal, setShowWalletModal] = useState(false);
  const [showAccountModal, setShowAccountModal] = useState(false);
  const { address, isConnected, chain } = useAccount();

  if (!isConnected) {
    return (
      <>
        <Button
          className="w-full bg-primary hover:bg-primary/90 text-primary-foreground"
          onClick={() => setShowWalletModal(true)}
        >
          <Wallet className="w-4 h-4 mr-2" />
          Connect Wallet
        </Button>
        <WalletSelectionModal
          open={showWalletModal}
          onOpenChange={setShowWalletModal}
        />
      </>
    );
  }

  return (
    <>
      <Button
        className="bg-primary hover:bg-primary/90 text-primary-foreground"
        onClick={() => setShowAccountModal(true)}
      >
        <div className="flex items-center gap-2">
          <div className="w-2 h-2 bg-green-500 rounded-full" />
          <span className="hidden sm:inline">
            {address?.slice(0, 6)}...{address?.slice(-4)}
          </span>
          <span className="sm:hidden">Connected</span>
          <ChevronDown className="w-4 h-4" />
        </div>
      </Button>

      <AccountDetailsModal
        open={showAccountModal}
        onOpenChange={setShowAccountModal}
      />
    </>
  );
}
