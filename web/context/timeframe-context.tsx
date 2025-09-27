"use client";

import { createContext, useState, useContext, ReactNode } from "react";

export type Timeframe = "5m" | "30m" | "1h" | "5h" | "24h";

interface TimeframeContextType {
  selectedTimeframe: Timeframe;
  setSelectedTimeframe: (timeframe: Timeframe) => void;
  availableTimeframes: { value: Timeframe; label: string; interval: number }[];
}

const TimeframeContext = createContext<TimeframeContextType | undefined>(
  undefined
);

export const TimeframeProvider = ({ children }: { children: ReactNode }) => {
  const [selectedTimeframe, setSelectedTimeframe] = useState<Timeframe>("1h");

  const availableTimeframes = [
    { value: "5m" as Timeframe, label: "5m", interval: 5 * 60 * 1000 }, // 5 minutes
    { value: "30m" as Timeframe, label: "30m", interval: 30 * 60 * 1000 }, // 30 minutes
    { value: "1h" as Timeframe, label: "1h", interval: 60 * 60 * 1000 }, // 1 hour
    { value: "5h" as Timeframe, label: "5h", interval: 5 * 60 * 60 * 1000 }, // 5 hours
    { value: "24h" as Timeframe, label: "24h", interval: 24 * 60 * 60 * 1000 }, // 24 hours
  ];

  return (
    <TimeframeContext.Provider
      value={{
        selectedTimeframe,
        setSelectedTimeframe,
        availableTimeframes,
      }}
    >
      {children}
    </TimeframeContext.Provider>
  );
};

export const useTimeframe = () => {
  const context = useContext(TimeframeContext);
  if (context === undefined) {
    throw new Error("useTimeframe must be used within a TimeframeProvider");
  }
  return context;
};
