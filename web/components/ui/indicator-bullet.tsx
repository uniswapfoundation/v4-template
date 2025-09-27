"use client";

import { motion, AnimatePresence } from "motion/react";
import { cn } from "@/lib/core";

interface IndicatorBulletProps {
  count?: number;
  variant?: "default" | "primary" | "destructive";
  className?: string;
}

export function IndicatorBullet({
  count = 0,
  variant = "default",
  className,
}: IndicatorBulletProps) {
  const hasCount = count > 0;

  const variants = {
    default: "bg-foreground",
    primary: "bg-primary-foreground",
    destructive: "bg-destructive-foreground",
  };

  return (
    <motion.div
      layout
      className={cn(
        "flex items-center justify-center rounded-full transition-all duration-200",
        hasCount
          ? "min-w-5 h-5 px-1" // Numbered state - wider for text
          : "w-2 h-2", // Bullet state - small dot
        variants[variant],
        className
      )}
      initial={false}
      animate={{
        scale: hasCount ? 1 : 1,
      }}
      transition={{
        layout: { duration: 0.2, ease: "easeOut" },
        scale: { duration: 0.15, ease: "easeOut" },
      }}
    >
      <AnimatePresence mode="wait">
        {hasCount && (
          <motion.span
            key={count}
            initial={{ opacity: 0, scale: 0.5 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 0.5 }}
            transition={{ duration: 0.15, ease: "easeOut" }}
            className="text-xs font-medium leading-none"
          >
            {count > 99 ? "99+" : count}
          </motion.span>
        )}
      </AnimatePresence>
    </motion.div>
  );
}
