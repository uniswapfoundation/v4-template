// Auto-generated minimal contract mapping using ABIs from foundry out/ artifacts.
// Do NOT edit ABIs manually; they are imported from compiled artifacts.

import { readFileSync } from "fs";
import { join } from "path";

// Function to load ABI from out directory
function loadABI(contractName: string): any {
  const artifactPath = join(__dirname, "../out", `${contractName}.sol`, `${getContractFileName(contractName)}.json`);
  const artifact = JSON.parse(readFileSync(artifactPath, "utf8"));
  return artifact.abi;
}

// Helper function to map contract names to their file names
function getContractFileName(contractName: string): string {
  const fileNameMap: Record<string, string> = {
    "PositionManagerV2": "PositionManager",
  };
  return fileNameMap[contractName] || contractName;
}

// Load contract ABIs
const perpsRouterArtifact = { abi: loadABI("PerpsRouter") };
const positionManagerArtifact = { abi: loadABI("PositionManagerV2") };
const marginAccountArtifact = { abi: loadABI("MarginAccount") };
const marketManagerArtifact = { abi: loadABI("MarketManager") };
const fundingOracleArtifact = { abi: loadABI("FundingOracle") };
const perpsHookArtifact = { abi: loadABI("PerpsHook") };
const mockUSDCArtifact = { abi: loadABI("MockUSDC") };
const mockVETHArtifact = { abi: loadABI("MockVETH") };
const insuranceFundArtifact = { abi: loadABI("InsuranceFund") };
const liquidationEngineArtifact = { abi: loadABI("LiquidationEngine") };
const positionFactoryArtifact = { abi: loadABI("PositionFactory") };
const positionNFTArtifact = { abi: loadABI("PositionNFT") };

// Load Uniswap V4 Core contract ABIs
const iPoolManagerArtifact = { abi: loadABI("IPoolManager") };
const iPositionManagerArtifact = { abi: loadABI("IPositionManager") };

// Load Uniswap V4 test contracts for swapping
const poolSwapTestArtifact = { abi: loadABI("PoolSwapTest") };
const poolModifyLiquidityTestArtifact = { abi: loadABI("PoolModifyLiquidityTest") };

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
    positionFactory: ContractInfo;
    positionNFT: ContractInfo;
    poolManager: ContractInfo;
    uniswapPositionManager: ContractInfo;
    poolSwapTest: ContractInfo;
    poolModifyLiquidityTest: ContractInfo;
  };
}

export const externalContracts: ExternalContracts = {
  [UNICHAIN_SEPOLIA]: {
    perpsRouter: {
      address: "0x3186834c4321195fA6408547D8a6baCBFFf1c7F6",
      abi: perpsRouterArtifact.abi
    },
    positionManager: {
      address: "0xEf2e87dB4D4fAC433bdf511AC2835D982Ee008B3",
      abi: positionManagerArtifact.abi
    },
    marginAccount: {
      address: "0x7612E10a932fABFDA22fCD96a0d94d7bF56eCB2f",
      abi: marginAccountArtifact.abi
    },
    marketManager: {
      address: "0x19b294Adc3540B84d4b9b8F0093A6A1666bc7ba9",
      abi: marketManagerArtifact.abi
    },
    fundingOracle: {
      address: "0x9d50CD9b030855276865af602e3CB8f9A018771E",
      abi: fundingOracleArtifact.abi
    },
    perpsHook: {
      address: "0x0f945Efc17208057258a7919371A6440E95C1Ac8",
      abi: perpsHookArtifact.abi
    },
    mockUSDC: {
      address: "0xf1E3834935C739ab4Fde53c1ab02C67446d09418",
      abi: mockUSDCArtifact.abi
    },
    mockVETH: {
      address: "0x189AACdEaCE967e3091d0a76DD8DD11eF67c01Fe",
      abi: mockVETHArtifact.abi
    },
    insuranceFund: {
      address: "0x903B874dbb570140671D278Ba8CBc925D412EE04",
      abi: insuranceFundArtifact.abi
    },
    liquidationEngine: {
      address: "0xB4A1Cb82D6F3227FCD132612f93ab76d9D453487",
      abi: liquidationEngineArtifact.abi
    },
    positionFactory: {
      address: "0xfA36d52f286408A2285590010213f95CC9b39B89",
      abi: positionFactoryArtifact.abi
    },
    positionNFT: {
      address: "0x70432c8A88AB0394F82eE39e592761a1f46Cf3Ba",
      abi: positionNFTArtifact.abi
    },
    // Uniswap V4 Core Contracts
    poolManager: {
      address: "0x00B036B58a818B1BC34d502D3fE730Db729e62AC",
      abi: iPoolManagerArtifact.abi
    },
    uniswapPositionManager: {
      address: "0xf969aee60879c54baaed9f3ed26147db216fd664",
      abi: iPositionManagerArtifact.abi
    },
    // Uniswap V4 Test Contracts for Swapping
    poolSwapTest: {
      address: "0x9140a78c1a137c7ff1c151ec8231272af78a99a4",
      abi: poolSwapTestArtifact.abi
    },
    poolModifyLiquidityTest: {
      address: "0x5fa728c0a5cfd51bee4b060773f50554c0c8a7ab",
      abi: poolModifyLiquidityTestArtifact.abi
    }
  }
};

export function getContracts(chainId: number = UNICHAIN_SEPOLIA) {
  const c = externalContracts[chainId];
  if (!c) throw new Error(`No contracts mapping for chain ${chainId}`);
  return c;
}
