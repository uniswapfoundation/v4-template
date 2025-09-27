import type React from "react";
import { Roboto_Mono } from "next/font/google";
import "./globals.css";
import type { Metadata } from "next";
import { V0Provider } from "@/lib/context";
import localFont from "next/font/local";
import { WagmiProviders } from "@/components/providers/wagmi-provider";
import { QueryProvider } from "@/components/providers/query-provider";
import { MarketProvider } from "@/context/market-context";
import { TimeframeProvider } from "@/context/timeframe-context";
import { PortfolioRefreshProvider } from "@/context/portfolio-refresh-context";
import { Toaster } from "@/components/ui/sonner";
import { ThemeProvider } from "@/components/theme-provider";

const robotoMono = Roboto_Mono({
  variable: "--font-roboto-mono",
  subsets: ["latin"],
});

const rebelGrotesk = localFont({
  src: "../public/fonts/Rebels-Fett.woff2",
  variable: "--font-rebels",
  display: "swap",
});

const isV0 = process.env["VERCEL_URL"]?.includes("vusercontent.net") ?? false;

export const metadata: Metadata = {
  title: {
    template: "%s – UNIPERP Trading",
    default: "UNIPERP Trading",
  },
  description:
    "Advanced trading interface for rebels. Trade with precision and style.",
  generator: "v0.app",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="dark">
      <head>
        <link
          rel="preload"
          href="/fonts/Rebels-Fett.woff2"
          as="font"
          type="font/woff2"
          crossOrigin="anonymous"
        />
      </head>
      <body
        className={`${rebelGrotesk.variable} ${robotoMono.variable} antialiased`}
      >
        <V0Provider isV0={isV0}>
          <ThemeProvider
            attribute="class"
            defaultTheme="dark"
            enableSystem
            disableTransitionOnChange
          >
            <QueryProvider>
              <WagmiProviders>
                <MarketProvider>
                  <TimeframeProvider>
                    <PortfolioRefreshProvider>
                      <div className="min-h-screen bg-background">
                        {children}
                      </div>
                      <Toaster />
                    </PortfolioRefreshProvider>
                  </TimeframeProvider>
                </MarketProvider>
              </WagmiProviders>
            </QueryProvider>
          </ThemeProvider>
        </V0Provider>
      </body>
    </html>
  );
}
