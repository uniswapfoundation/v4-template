"use client";

import { Button } from "@/components/ui/button";
import { useTimeframe } from "@/context/timeframe-context";

export default function TimeframeSelector() {
  const { selectedTimeframe, setSelectedTimeframe, availableTimeframes } =
    useTimeframe();

  return (
    <div className="flex items-center gap-1">
      {availableTimeframes.map((timeframe) => (
        <Button
          key={timeframe.value}
          variant={selectedTimeframe === timeframe.value ? "default" : "ghost"}
          size="sm"
          onClick={() => setSelectedTimeframe(timeframe.value)}
          className="text-xs px-2 py-1 h-7 min-w-[2.5rem]"
        >
          {timeframe.label}
        </Button>
      ))}
    </div>
  );
}
