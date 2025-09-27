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
      address: "0xB39d6b44437b1036f2C42bb1Fd490F5381dD22dc",
      abi: perpsRouterArtifact.abi
    },
    positionManager: {
      address: "0x6B97C3E3fde7a2B06eF860622D7b5a847a34E81e",
      abi: positionManagerArtifact.abi
    },
    marginAccount: {
      address: "0xBcc2b27C15518Ee4923dcc643521F47A37514694",
      abi: marginAccountArtifact.abi
    },
    marketManager: {
      address: "0xEF836549F8CA5d9396683f3e0ECE67348AF2c07b",
      abi: marketManagerArtifact.abi
    },
    fundingOracle: {
      address: "0x8EBbAe5e8dA96f000C940CAc2e224EC83D0994CB",
      abi: fundingOracleArtifact.abi
    },
    perpsHook: {
      address: "0x937c62fe13D4B8e51967b6cCC55605AA965A5aC8",
      abi: perpsHookArtifact.abi
    },
    mockUSDC: {
      address: "0x748Da545386651D3d83B4AbC6267153fF2BdF91d",
      abi: mockUSDCArtifact.abi
    },
    mockVETH: {
      address: "0x982d92a8593c0C3c0C4F8558b8C80245d758213e",
      abi: mockVETHArtifact.abi
    },
    insuranceFund: {
      address: "0x33E3a44781F5c12Eb35Fc4b304A5823591eaB51b",
      abi: insuranceFundArtifact.abi
    },
    liquidationEngine: {
      address: "0x4822184C495E33976DF10BD68C8Bb161Fa96927A",
      abi: liquidationEngineArtifact.abi
    },
    positionFactory: {
      address: "0x2c143D055b5c5EBd04BF8EeBa224284D280a8451",
      abi: positionFactoryArtifact.abi
    },
    positionNFT: {
      address: "0x8EB238Ab91a06DC616c631ebA3D64d48040d37e3",
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
