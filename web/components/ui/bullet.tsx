import { cn } from "@/lib/core";
import { cva, VariantProps } from "class-variance-authority";
import React, { HTMLAttributes } from "react";

export const bulletVariants = cva("rounded-[1.5px]", {
  variants: {
    variant: {
      default: "bg-primary",
      success: "bg-success",
      warning: "bg-warning",
      destructive: "bg-destructive",
    },
    size: {
      sm: "size-2",
      default: "size-2.5",
      lg: "size-3",
    },
  },
  defaultVariants: {
    variant: "default",
    size: "default",
  },
});

export interface BulletProps
  extends VariantProps<typeof bulletVariants>,
    HTMLAttributes<HTMLDivElement> {}

export const Bullet = ({ variant, size, className, ...props }: BulletProps) => {
  return (
    <div
      className={cn(bulletVariants({ variant, size }), className)}
      {...props}
    ></div>
  );
};
