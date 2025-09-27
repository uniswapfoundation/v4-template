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
      address: "0x0B5B1aF93438455940F548bAc210A16e6A27669C",
      abi: perpsRouterArtifact.abi
    },
    positionManager: {
      address: "0xcFe240bE5C918d18DaC233DA08C9a3b71Adf7D18",
      abi: positionManagerArtifact.abi
    },
    marginAccount: {
      address: "0xaCF00c49717E0CF51CD7Bc8F2fcC17E6647c5148",
      abi: marginAccountArtifact.abi
    },
    marketManager: {
      address: "0x77B6C376b88fA602026e6ba1cD81aD9F8C867a8B",
      abi: marketManagerArtifact.abi
    },
    fundingOracle: {
      address: "0x006694437063034c29d8e8c41D56486a902B9BD2",
      abi: fundingOracleArtifact.abi
    },
    perpsHook: {
      address: "0xca17bc76e3882Dc2df766D9A1b6690a57449Dac8",
      abi: perpsHookArtifact.abi
    },
    mockUSDC: {
      address: "0x022d625B4B8dcA331afdE3879A2FD1A5b66239e1",
      abi: mockUSDCArtifact.abi
    },
    mockVETH: {
      address: "0x8CB741567B4dEaE5c78A9ca9284b6B807974f72f",
      abi: mockVETHArtifact.abi
    },
    insuranceFund: {
      address: "0x066DeF0AC376E6363763272ae0Aa1aE4012E4a42",
      abi: insuranceFundArtifact.abi
    },
    liquidationEngine: {
      address: "0x877A9334ca7323544065FCed5a351b7D057Cf826",
      abi: liquidationEngineArtifact.abi
    },
    positionFactory: {
      address: "0xd1a79AA958dad1D89b6Ba94EFe597dE0cA380dD3",
      abi: positionFactoryArtifact.abi
    },
    positionNFT: {
      address: "0x25F273b73Db9f7EcA7aa9C7BBc6f1acfD4A6D22f",
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
