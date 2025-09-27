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
      address: "0x683d4203587827F5658E0D09A832dCe374343553",
      abi: perpsRouterArtifact.abi,
    },
    positionManager: {
      address: "0x5c5e20e9c600443040A770ce6A83840fdD1e4E22",
      abi: positionManagerArtifact.abi,
    },
    marginAccount: {
      address: "0x7A191127944E3f5cC1C5D10B3991B03A82cAE791",
      abi: marginAccountArtifact.abi,
    },
    marketManager: {
      address: "0x2a98c921688eD538833509772dd5E33e43a6215b",
      abi: marketManagerArtifact.abi,
    },
    fundingOracle: {
      address: "0x8B262Ed4d0A11326f201D6ef41539825cb89B35a",
      abi: fundingOracleArtifact.abi,
    },
    perpsHook: {
      address: "0xFe66Ae40cec317ec314cD6865fe23D79281e9Ac8",
      abi: perpsHookArtifact.abi,
    },
    mockUSDC: {
      address: "0x898d058e8f64D4e744b6B19f9967EdF1BAd9e111",
      abi: mockUSDCArtifact.abi,
    },
    mockVETH: {
      address: "0x03AFC3714cFB3B49CC8fe1CE23De2B24751D5d97",
      abi: mockVETHArtifact.abi,
    },
    insuranceFund: {
      address: "0x2754BA7d581c9B1135Bb595baa030fEc47a06810",
      abi: insuranceFundArtifact.abi,
    },
    liquidationEngine: {
      address: "0x4A18FDa1A6F757Bbea5513A0fe56371FFb613b29",
      abi: liquidationEngineArtifact.abi,
    },
    positionFactory: {
      address: "0x3113ABFbb24e5c24764BA720130021aF34497706",
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
