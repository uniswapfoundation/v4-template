// Unichain Sepolia chain id
export const UNICHAIN_SEPOLIA = 1301;

// Minimal ABIs for the contracts we need
const marginAccountABI = [
  {
    inputs: [{ name: "user", type: "address" }],
    name: "getTotalBalance",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "user", type: "address" }],
    name: "freeBalance",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "user", type: "address" }],
    name: "lockedBalance",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "amount", type: "uint256" }],
    name: "deposit",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [{ name: "amount", type: "uint256" }],
    name: "withdraw",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
] as const;

const mockUSDCABI = [
  {
    inputs: [{ name: "account", type: "address" }],
    name: "balanceOf",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    name: "approve",
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    name: "allowance",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

const positionManagerABI = [
  {
    inputs: [
      { name: "marketId", type: "bytes32" },
      { name: "sizeBase", type: "int256" },
      { name: "entryPrice", type: "uint256" },
      { name: "margin", type: "uint256" },
    ],
    name: "openPosition",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { name: "user", type: "address" },
      { name: "marketId", type: "bytes32" },
      { name: "sizeBase", type: "int256" },
      { name: "entryPrice", type: "uint256" },
      { name: "margin", type: "uint256" },
    ],
    name: "openPositionFor",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { name: "tokenId", type: "uint256" },
      { name: "exitPrice", type: "uint256" },
    ],
    name: "closePosition",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { name: "tokenId", type: "uint256" },
      { name: "newSizeBase", type: "int256" },
      { name: "newMargin", type: "uint256" },
    ],
    name: "updatePosition",
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [{ name: "tokenId", type: "uint256" }],
    name: "getPosition",
    outputs: [
      {
        components: [
          { name: "owner", type: "address" },
          { name: "margin", type: "uint96" },
          { name: "marketId", type: "bytes32" },
          { name: "sizeBase", type: "int256" },
          { name: "entryPrice", type: "uint256" },
          { name: "lastFundingIndex", type: "uint256" },
          { name: "openedAt", type: "uint64" },
          { name: "fundingPaid", type: "int256" },
        ],
        name: "",
        type: "tuple",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { name: "tokenId", type: "uint256" },
      { name: "currentPrice", type: "uint256" },
    ],
    name: "getUnrealizedPnL",
    outputs: [{ name: "", type: "int256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "user", type: "address" }],
    name: "getUserPositions",
    outputs: [{ name: "", type: "uint256[]" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

const fundingOracleABI = [
  {
    inputs: [{ name: "poolId", type: "bytes32" }],
    name: "getMarkPrice",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

type MarginAccountAbi = typeof marginAccountABI;
type MockUSDCAbi = typeof mockUSDCABI;

interface ContractInfo<A = MarginAccountAbi> {
  address: `0x${string}`;
  abi: A;
}

interface ExternalContracts {
  [chainId: number]: {
    marginAccount: ContractInfo<MarginAccountAbi>;
    mockUSDC: ContractInfo<MockUSDCAbi>;
    positionManager: ContractInfo;
    fundingOracle: ContractInfo;
    perpsHook: ContractInfo;
    mockVETH: ContractInfo;
  };
}

export const externalContracts: ExternalContracts = {
  [UNICHAIN_SEPOLIA]: {
    marginAccount: {
      address: "0x4Aa68070609C7EE42CDd7E431F202c0577c8556E",
      abi: marginAccountABI,
    },
    mockUSDC: {
      address: "0xb2feD1a40Fe6CA0be97Cde27e1D2dF1CC65Fd101",
      abi: mockUSDCABI,
    },
    // Add other contract addresses from the working script
    positionManager: {
      address: "0xD919D9FA466fD3e88640F97700640fbBb3214eB2",
      abi: positionManagerABI,
    },
    fundingOracle: {
      address: "0xB07387d2ddF33372C9AE9D5aBe8f0850BD54444d",
      abi: fundingOracleABI,
    },
    perpsHook: {
      address: "0x06cB25A0F63D88EAED5cb7273d4fab8516B41ac8",
      abi: [],
    },
    mockVETH: {
      address: "0x7f7FD1D6A6BF6225F4872Fc8aa165E43Bf22D30c",
      abi: [],
    },
  },
};

export function getContracts(chainId: number = UNICHAIN_SEPOLIA) {
  const c = externalContracts[chainId];
  if (!c) throw new Error(`No contracts mapping for chain ${chainId}`);
  return c;
}
