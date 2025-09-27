import TradingNavbar from "@/components/trading/navbar";
import TradingChart from "@/components/trading/chart";
import OrderBook from "@/components/trading/orderbook";
import TradingPanel from "@/components/trading/trading-panel";
import Portfolio from "@/components/trading/portfolio";
import MarketSelectionModal from "@/components/trading/market-selection-modal";

export default function TradingPage() {
  return (
    <div className="min-h-screen bg-background">
      <TradingNavbar />
      <div className="flex flex-col lg:flex-row h-[calc(100vh-73px)]">
        {/* Left Section - Chart and Portfolio */}
        <div className="flex-1 p-2 md:p-4 flex flex-col gap-2 md:gap-4">
          <div className="h-[300px] sm:h-[400px] lg:h-[60%]">
            <TradingChart />
          </div>

          <div className="h-[300px] sm:h-[400px] lg:h-[40%]">
            <Portfolio />
          </div>
        </div>

        {/* Order Book and Trading Panel - Responsive Layout */}
        <div className="flex flex-col md:flex-row lg:flex-row lg:w-auto">
          {/* Order Book with Trades - Center Section */}
          <div className="w-full md:w-1/2 lg:w-80 p-2 md:p-4 lg:pl-0">
            <OrderBook />
          </div>

          {/* Trading Panel - Right Section */}
          <div className="w-full md:w-1/2 lg:w-80 p-2 md:p-4 lg:pl-0">
            <TradingPanel />
          </div>
        </div>
      </div>
    </div>
  );
}
