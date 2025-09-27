// Contract mapping using existing ABI files
import { readFileSync } from "fs";
import { join } from "path";

// Function to load ABI from local out directory
function loadABI(contractName: string): any {
  const fileName = getContractFileName(contractName);
  const artifactPath = join(
    __dirname,
    "out",
    `${contractName}.sol`,
    `${fileName}.json`
  );
  const artifact = JSON.parse(readFileSync(artifactPath, "utf8"));
  return artifact.abi;
}

// Helper function to map contract names to their file names
function getContractFileName(contractName: string): string {
  const fileNameMap: Record<string, string> = {
    PositionManagerV2: "PositionManager",
  };
  return fileNameMap[contractName] || contractName;
}

// Load contract ABIs from existing files
const perpsRouterArtifact = { abi: loadABI("PerpsRouter") };
const marginAccountArtifact = { abi: loadABI("MarginAccount") };
const mockUSDCArtifact = { abi: loadABI("MockUSDC") };
const positionManagerArtifact = { abi: loadABI("PositionManagerV2") };
const fundingOracleArtifact = { abi: loadABI("FundingOracle") };
const perpsHookArtifact = { abi: loadABI("PerpsHook") };
const mockVETHArtifact = { abi: loadABI("MockVETH") };
const insuranceFundArtifact = { abi: loadABI("InsuranceFund") };
const liquidationEngineArtifact = { abi: loadABI("LiquidationEngine") };
const positionFactoryArtifact = { abi: loadABI("PositionFactory") };
const marketManagerArtifact = { abi: loadABI("MarketManagerV2") };

// For contracts that don't have ABI files yet, we'll use minimal ABIs
const iPoolManagerArtifact = { abi: [] };
const iPositionManagerArtifact = { abi: [] };
const poolSwapTestArtifact = { abi: [] };
const poolModifyLiquidityTestArtifact = { abi: [] };

// Unichain Sepolia chain id (placeholder - update if different)
export const UNICHAIN_SEPOLIA = 1301;

type Abi = typeof perpsRouterArtifact.abi;

interface ContractInfo<A = Abi> {
  address: `0x${string}`;
  abi: A;
}

interface ExternalContracts {
  [chainId: number]: {
    perpsRouter: ContractInfo;
    positionManager: ContractInfo;
    marginAccount: ContractInfo;
    marketManager: ContractInfo;
    fundingOracle: ContractInfo;
    perpsHook: ContractInfo;
    mockUSDC: ContractInfo;
    mockVETH: ContractInfo;
    insuranceFund: ContractInfo;
    liquidationEngine: ContractInfo;
    poolManager: ContractInfo;
    uniswapPositionManager: ContractInfo;
    poolSwapTest: ContractInfo;
    poolModifyLiquidityTest: ContractInfo;
  };
}

export const externalContracts: ExternalContracts = {
  [UNICHAIN_SEPOLIA]: {
    perpsRouter: {
      address: "0x88e9ae14e9b18417bBdB9e5EA0B836F4DB5093af",
      abi: perpsRouterArtifact.abi,
    },
    positionManager: {
      address: "0xD919D9FA466fD3e88640F97700640fbBb3214eB2",
      abi: positionManagerArtifact.abi,
    },
    marginAccount: {
      address: "0x4Aa68070609C7EE42CDd7E431F202c0577c8556E",
      abi: marginAccountArtifact.abi,
    },
    marketManager: {
      address: "0x222a07FB1ee309d2e6839e20B384E9DadaAB8D5b",
      abi: marketManagerArtifact.abi,
    },
    fundingOracle: {
      address: "0xB07387d2ddF33372C9AE9D5aBe8f0850BD54444d",
      abi: fundingOracleArtifact.abi,
    },
    perpsHook: {
      address: "0x06cB25A0F63D88EAED5cb7273d4fab8516B41ac8",
      abi: perpsHookArtifact.abi,
    },
    mockUSDC: {
      address: "0xb2feD1a40Fe6CA0be97Cde27e1D2dF1CC65Fd101",
      abi: mockUSDCArtifact.abi,
    },
    mockVETH: {
      address: "0x7f7FD1D6A6BF6225F4872Fc8aa165E43Bf22D30c",
      abi: mockVETHArtifact.abi,
    },
    insuranceFund: {
      address: "0x4F7a720494f11B7A2e82e9fe7236F09631C9602F",
      abi: insuranceFundArtifact.abi,
    },
    liquidationEngine: {
      address: "0xC037B7cfF8485971E1B1125e7B4Ed1Acc3f6acfd",
      abi: liquidationEngineArtifact.abi,
    },
    positionFactory: {
      address: "0xFdB6179d9778942Db01C189791c8199350a149e1",
      abi: positionFactoryArtifact.abi,
    },
    // Uniswap V4 Core Contracts
    poolManager: {
      address: "0x00B036B58a818B1BC34d502D3fE730Db729e62AC",
      abi: iPoolManagerArtifact.abi,
    },
    uniswapPositionManager: {
      address: "0xf969aee60879c54baaed9f3ed26147db216fd664",
      abi: iPositionManagerArtifact.abi,
    },
    // Uniswap V4 Test Contracts for Swapping
    poolSwapTest: {
      address: "0x9140a78c1a137c7ff1c151ec8231272af78a99a4",
      abi: poolSwapTestArtifact.abi,
    },
    poolModifyLiquidityTest: {
      address: "0x5fa728c0a5cfd51bee4b060773f50554c0c8a7ab",
      abi: poolModifyLiquidityTestArtifact.abi,
    },
  },
};

export function getContracts(chainId: number = UNICHAIN_SEPOLIA) {
  const c = externalContracts[chainId];
  if (!c) throw new Error(`No contracts mapping for chain ${chainId}`);
  return c;
}
