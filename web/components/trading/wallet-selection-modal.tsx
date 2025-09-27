"use client"

import { useConnect } from "wagmi"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { X } from "lucide-react"

interface WalletSelectionModalProps {
  open: boolean
  onOpenChange: (open: boolean) => void
}

const walletIcons = {
  MetaMask: (
    <svg width="24" height="24" viewBox="0 0 24 24" fill="none">
      <path
        d="M22.56 6.25L13.5 1.25C12.58 0.75 11.42 0.75 10.5 1.25L1.44 6.25C0.52 6.75 0 7.75 0 8.75V15.25C0 16.25 0.52 17.25 1.44 17.75L10.5 22.75C11.42 23.25 12.58 23.25 13.5 22.75L22.56 17.75C23.48 17.25 24 16.25 24 15.25V8.75C24 7.75 23.48 6.75 22.56 6.25Z"
        fill="#F6851B"
      />
      <path
        d="M12 16C14.21 16 16 14.21 16 12C16 9.79 14.21 8 12 8C9.79 8 8 9.79 8 12C8 14.21 9.79 16 12 16Z"
        fill="#E2761B"
      />
    </svg>
  ),
  "Coinbase Wallet": (
    <svg width="24" height="24" viewBox="0 0 24 24" fill="none">
      <rect width="24" height="24" rx="12" fill="#0052FF" />
      <path
        d="M12 6C8.69 6 6 8.69 6 12C6 15.31 8.69 18 12 18C15.31 18 18 15.31 18 12C18 8.69 15.31 6 12 6ZM12 15C10.34 15 9 13.66 9 12C9 10.34 10.34 9 12 9C13.66 9 15 10.34 15 12C15 13.66 13.66 15 12 15Z"
        fill="white"
      />
    </svg>
  ),
  WalletConnect: (
    <svg width="24" height="24" viewBox="0 0 24 24" fill="none">
      <rect width="24" height="24" rx="12" fill="#3B99FC" />
      <path
        d="M7.5 9.75C10.74 6.51 16.26 6.51 19.5 9.75L20.25 10.5C20.4 10.65 20.4 10.89 20.25 11.04L19.14 12.15C19.065 12.225 18.935 12.225 18.86 12.15L18.36 11.65C16.14 9.43 12.36 9.43 10.14 11.65L9.61 12.18C9.535 12.255 9.405 12.255 9.33 12.18L8.22 11.07C8.07 10.92 8.07 10.68 8.22 10.53L7.5 9.75Z"
        fill="white"
      />
    </svg>
  ),
}

export function WalletSelectionModal({ open, onOpenChange }: WalletSelectionModalProps) {
  const { connect, connectors, isPending } = useConnect()

  const handleConnect = (connector: any) => {
    connect({ connector })
    onOpenChange(false)
  }

  const getWalletDisplayName = (connectorName: string) => {
    if (connectorName.includes("MetaMask")) return "MetaMask"
    if (connectorName.includes("Coinbase")) return "Coinbase Wallet"
    if (connectorName.includes("WalletConnect")) return "WalletConnect"
    return connectorName
  }

  const getWalletDescription = (connectorName: string) => {
    if (connectorName.includes("MetaMask")) return "Connect using browser extension"
    if (connectorName.includes("Coinbase")) return "Connect using Coinbase Wallet"
    if (connectorName.includes("WalletConnect")) return "Connect using mobile wallet"
    return "Connect using wallet"
  }

  const filteredConnectors = connectors.filter(
    (connector) =>
      !connector.name.toLowerCase().includes("injected") &&
      (connector.name.includes("MetaMask") ||
        connector.name.includes("Coinbase") ||
        connector.name.includes("WalletConnect")),
  )

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center justify-between">
            Connect Wallet
            <Button variant="ghost" size="sm" onClick={() => onOpenChange(false)} className="h-6 w-6 p-0">
              <X className="h-4 w-4" />
            </Button>
          </DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          {filteredConnectors.map((connector) => {
            const displayName = getWalletDisplayName(connector.name)
            const description = getWalletDescription(connector.name)
            const icon = walletIcons[displayName as keyof typeof walletIcons]

            return (
              <Button
                key={connector.uid}
                variant="outline"
                className="w-full h-16 justify-start gap-4 hover:bg-accent bg-transparent"
                onClick={() => handleConnect(connector)}
                disabled={isPending}
              >
                <div className="flex-shrink-0">
                  {icon || <div className="w-6 h-6 bg-gradient-to-br from-blue-500 to-purple-600 rounded-full" />}
                </div>
                <div className="flex flex-col items-start">
                  <span className="font-medium">{displayName}</span>
                  <span className="text-xs text-muted-foreground">{description}</span>
                </div>
              </Button>
            )
          })}
        </div>
        <div className="text-xs text-muted-foreground text-center mt-4">
          By connecting a wallet, you agree to our Terms of Service
        </div>
      </DialogContent>
    </Dialog>
  )
}
