"use client";

import { createContext, useContext, ReactNode } from "react";

// V0 Context
type V0ContextType = {
  isV0: boolean;
};

const V0Context = createContext<V0ContextType | undefined>(undefined);

type V0ProviderProps = {
  children: ReactNode;
  isV0: boolean;
};

export const V0Provider = ({ children, isV0 }: V0ProviderProps) => {
  return <V0Context.Provider value={{ isV0 }}>{children}</V0Context.Provider>;
};

export const useIsV0 = (): boolean => {
  const context = useContext(V0Context);
  if (context === undefined) {
    throw new Error("useIsV0 must be used within a V0Provider");
  }
  return context.isV0;
};
