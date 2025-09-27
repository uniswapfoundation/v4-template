// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {MarginAccount} from "../src/MarginAccount.sol";
import {InsuranceFund} from "../src/InsuranceFund.sol";
import {FundingOracle} from "../src/FundingOracle.sol";
import {PerpsRouter} from "../src/PerpsRouter.sol";
import {PositionManager} from "../src/PositionManagerV2.sol";
import {PositionFactory} from "../src/PositionFactory.sol";
import {PositionNFT} from "../src/PositionNFT.sol";
import {MarketManager} from "../src/MarketManager.sol";
import {PerpsHook} from "../src/PerpsHook.sol";
import {LiquidationEngine} from "../src/LiquidationEngine.sol";

// Mock contracts
import {MockUSDC} from "../test/utils/mocks/MockUSDC.sol";
import {MockVETH} from "../test/utils/mocks/MockVETH.sol";

/// @title Production Deployment Script
/// @notice Deploys the complete Perpetual Futures Protocol to production
/// @dev Uses Mock USDC instead of real USDC for testing purposes
contract DeployProductionScript is Script {
    using stdJson for string;
    
    // Contract instances
    MockUSDC public mockUSDC;
    MockVETH public mockVETH;
    MarginAccount public marginAccount;
    InsuranceFund public insuranceFund;
    FundingOracle public fundingOracle;
    PerpsRouter public perpsRouter;
    PositionManager public positionManager;
    PositionFactory public positionFactory;
    PositionNFT public positionNFT;
    MarketManager public marketManager;
    PerpsHook public perpsHook;
    LiquidationEngine public liquidationEngine;
    
    // Configuration
    address public deployer;
    uint256 public deployerPrivateKey;
    string public deploymentNetwork;
    
    // Uniswap V4 addresses (would be different per network)
    IPoolManager public constant POOL_MANAGER_PLACEHOLDER = IPoolManager(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
    
    // Pyth Network addresses per chain
    mapping(string => address) public pythContracts;
    
    // Initial configuration values
    uint256 public constant INITIAL_INSURANCE_FUND = 50_000e6; // $50,000 USDC
    uint256 public constant INITIAL_DEPLOYER_USDC = 1_000_000e6; // $1M USDC for testing
    
    function setUp() public {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);
        deploymentNetwork = vm.envString("DEPLOYMENT_NETWORK");
        
        // Configure Pyth contract addresses per network
        pythContracts["anvil"] = address(0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF); // Placeholder
        pythContracts["sepolia"] = 0xDd24F84d36BF92C65F92307595335bdFab5Bbd21; // Pyth Sepolia
        pythContracts["mainnet"] = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6; // Pyth Mainnet
        pythContracts["arbitrum"] = 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C; // Pyth Arbitrum
        pythContracts["polygon"] = 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C; // Pyth Polygon
    }
    
    function run() external {
        console.log("==============================================");
        console.log("PERPETUAL FUTURES PROTOCOL - PRODUCTION DEPLOYMENT");
        console.log("==============================================");
        console.log("Network:", deploymentNetwork);
        console.log("Deployer:", deployer);
        console.log("==============================================\n");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Phase 1: Deploy Token Infrastructure
        console.log("PHASE 1: Deploying Token Infrastructure");
        console.log("----------------------------------------");
        deployTokens();
        
        // Phase 2: Deploy Core Protocol Contracts
        console.log("\nPHASE 2: Deploying Core Protocol Contracts");
        console.log("------------------------------------------");
        deployCoreContracts();
        
        // Phase 3: Deploy Uniswap V4 Integration
        console.log("\nPHASE 3: Deploying Uniswap V4 Integration");
        console.log("-----------------------------------------");
        deployUniswapIntegration();
        
        // Phase 4: Deploy Liquidation System
        console.log("\nPHASE 4: Deploying Liquidation System");
        console.log("------------------------------------");
        deployLiquidationEngine();
        
        // Phase 5: Setup Authorizations and Configurations
        console.log("\nPHASE 5: Setting up Authorizations and Configurations");
        console.log("-----------------------------------------------------");
        setupAuthorizations();
        setupConfigurations();
        
        // Phase 6: Initial Funding and Market Setup
        console.log("\nPHASE 6: Initial Funding and Market Setup");
        console.log("-----------------------------------------");
        initialFunding();
        
        vm.stopBroadcast();
        
        // Phase 7: Generate Deployment Report
        console.log("\nPHASE 7: Generating Deployment Report");
        console.log("------------------------------------");
        generateDeploymentReport();
        
        console.log("\n==============================================");
        console.log("DEPLOYMENT COMPLETED SUCCESSFULLY!");
        console.log("==============================================");
    }
    
    function deployTokens() internal {
        console.log("1. Deploying MockUSDC...");
        mockUSDC = new MockUSDC();
        console.log("   MockUSDC deployed at:", address(mockUSDC));
        
        console.log("2. Deploying MockVETH...");
        mockVETH = new MockVETH();
        console.log("   MockVETH deployed at:", address(mockVETH));
        
        // Mint initial supply to deployer
        mockUSDC.mint(deployer, INITIAL_DEPLOYER_USDC);
        mockVETH.mint(deployer, 1000e18); // 1000 VETH for testing
        
        console.log("   Initial USDC minted to deployer:", INITIAL_DEPLOYER_USDC / 1e6, "USDC");
        console.log("   Initial VETH minted to deployer: 1000 VETH");
    }
    
    function deployCoreContracts() internal {
        console.log("1. Deploying MarginAccount...");
        marginAccount = new MarginAccount(address(mockUSDC));
        console.log("   MarginAccount deployed at:", address(marginAccount));
        
        console.log("2. Deploying InsuranceFund...");
        insuranceFund = new InsuranceFund(address(mockUSDC));
        console.log("   InsuranceFund deployed at:", address(insuranceFund));
        
        console.log("3. Deploying FundingOracle...");
        address pythContract = pythContracts[deploymentNetwork];
        require(pythContract != address(0), "Pyth contract not configured for this network");
        fundingOracle = new FundingOracle(pythContract);
        console.log("   FundingOracle deployed at:", address(fundingOracle));
        console.log("   Using Pyth contract at:", pythContract);
    }
    
    function deployUniswapIntegration() internal {
        console.log("1. Deploying modular PositionManager system...");
        
        // Deploy PositionFactory
        positionFactory = new PositionFactory(
            address(mockUSDC),
            address(marginAccount)
        );
        console.log("   PositionFactory deployed at:", address(positionFactory));
        
        // Deploy PositionNFT
        positionNFT = new PositionNFT();
        console.log("   PositionNFT deployed at:", address(positionNFT));
        
        // Deploy MarketManager
        marketManager = new MarketManager();
        console.log("   MarketManager deployed at:", address(marketManager));
        
        // Deploy PositionManager
        positionManager = new PositionManager(
            address(positionFactory),
            address(positionNFT),
            address(marketManager)
        );
        console.log("   PositionManager deployed at:", address(positionManager));
        
        // Set up component relationships
        positionFactory.setPositionNFT(address(positionNFT));
        positionNFT.setFactory(address(positionFactory));
        
        console.log("2. Deploying PerpsHook...");
        perpsHook = new PerpsHook(
            POOL_MANAGER_PLACEHOLDER,
            positionManager,      // PositionManager (orchestrator)
            positionFactory,      // PositionFactory
            marginAccount,        // MarginAccount  
            fundingOracle,        // FundingOracle
            mockUSDC              // IERC20 (USDC)
        );
        console.log("   PerpsHook deployed at:", address(perpsHook));
        
        console.log("3. Deploying PerpsRouter...");
        perpsRouter = new PerpsRouter(
            address(positionFactory),
            address(positionNFT),
            address(marketManager),
            address(fundingOracle),
            address(POOL_MANAGER_PLACEHOLDER),
            address(mockUSDC)
        );
        console.log("   PerpsRouter deployed at:", address(perpsRouter));
    }
    
    function deployLiquidationEngine() internal {
        console.log("1. Deploying LiquidationEngine...");
        liquidationEngine = new LiquidationEngine(
            address(positionManager),
            address(positionFactory),
            address(marginAccount),
            address(fundingOracle),
            payable(address(insuranceFund)),
            address(mockUSDC)
        );
        console.log("   LiquidationEngine deployed at:", address(liquidationEngine));
    }
    
    function setupAuthorizations() internal {
        console.log("1. Setting up MarginAccount authorizations...");
        marginAccount.addAuthorizedContract(address(perpsRouter));
        marginAccount.addAuthorizedContract(address(positionManager));
        marginAccount.addAuthorizedContract(address(perpsHook));
        marginAccount.addAuthorizedContract(address(liquidationEngine));
        console.log("   SUCCESS: Authorized: PerpsRouter, PositionManager, PerpsHook, LiquidationEngine");
        
        console.log("2. Setting up InsuranceFund authorizations...");
        insuranceFund.addAuthorizedContract(address(perpsRouter));
        insuranceFund.addAuthorizedContract(address(positionManager));
        insuranceFund.addAuthorizedContract(address(perpsHook));
        insuranceFund.addAuthorizedContract(address(liquidationEngine));
        console.log("   SUCCESS: Authorized: PerpsRouter, PositionManager, PerpsHook, LiquidationEngine");
    }
    
    function setupConfigurations() internal {
        console.log("1. Configuring market parameters...");
        
        // Add ETH-USDC market to FundingOracle
        // For now, we'll use a simple approach without the complex market setup
        // In production, you would need to properly configure the PoolId and Pyth price feed
        console.log("   Market configuration skipped - requires proper PoolId and Pyth feed setup");
        console.log("   To configure markets, call fundingOracle.addMarket() manually with:");
        console.log("   - PoolId from actual Uniswap V4 pool");
        console.log("   - vAMM hook address"); 
        console.log("   - Pyth price feed ID for ETH/USD");
    }
    
    function initialFunding() internal {
        console.log("1. Funding InsuranceFund with initial capital...");
        
        // Approve and deposit to insurance fund
        mockUSDC.approve(address(insuranceFund), INITIAL_INSURANCE_FUND);
        insuranceFund.deposit(INITIAL_INSURANCE_FUND);
        
        console.log("   SUCCESS: InsuranceFund funded with:", INITIAL_INSURANCE_FUND / 1e6, "USDC");
        console.log("   Insurance Fund Balance:", insuranceFund.getBalance() / 1e6, "USDC");
    }
    
    function generateDeploymentReport() internal view {
        console.log("\n==============================================");
        console.log("DEPLOYMENT REPORT");
        console.log("==============================================");
        console.log("Network:", deploymentNetwork);
        console.log("Deployer:", deployer);
        console.log("Block Number:", block.number);
        console.log("Timestamp:", block.timestamp);
        console.log("----------------------------------------------");
        
        console.log("TOKEN CONTRACTS:");
        console.log("MockUSDC:         ", address(mockUSDC));
        console.log("MockVETH:         ", address(mockVETH));
        
        console.log("\nCORE CONTRACTS:");
        console.log("MarginAccount:    ", address(marginAccount));
        console.log("InsuranceFund:    ", address(insuranceFund));
        console.log("FundingOracle:    ", address(fundingOracle));
        
        console.log("\nUNISWAP V4 INTEGRATION:");
        console.log("PositionManager:  ", address(positionManager));
        console.log("PerpsHook:        ", address(perpsHook));
        console.log("PerpsRouter:      ", address(perpsRouter));
        
        console.log("\nLIQUIDATION SYSTEM:");
        console.log("LiquidationEngine:", address(liquidationEngine));
        
        console.log("\nEXTERNAL DEPENDENCIES:");
        console.log("PoolManager:      ", address(POOL_MANAGER_PLACEHOLDER));
        console.log("Pyth Contract:    ", pythContracts[deploymentNetwork]);
        
        console.log("\nINITIAL BALANCES:");
        console.log("Deployer USDC:    ", mockUSDC.balanceOf(deployer) / 1e6, "USDC");
        console.log("Deployer VETH:    ", mockVETH.balanceOf(deployer) / 1e18, "VETH");
        console.log("Insurance Fund:   ", insuranceFund.getBalance() / 1e6, "USDC");
        
        console.log("==============================================");
        
        // Generate JSON deployment file
        console.log("\nSave this deployment configuration:");
        console.log("{");
        console.log('  "network": "', deploymentNetwork, '",');
        console.log('  "deployer": "', deployer, '",');
        console.log('  "blockNumber": ', block.number, ',');
        console.log('  "timestamp": ', block.timestamp, ',');
        console.log('  "contracts": {');
        console.log('    "MockUSDC": "', address(mockUSDC), '",');
        console.log('    "MockVETH": "', address(mockVETH), '",');
        console.log('    "MarginAccount": "', address(marginAccount), '",');
        console.log('    "InsuranceFund": "', address(insuranceFund), '",');
        console.log('    "FundingOracle": "', address(fundingOracle), '",');
        console.log('    "PositionManager": "', address(positionManager), '",');
        console.log('    "PerpsHook": "', address(perpsHook), '",');
        console.log('    "PerpsRouter": "', address(perpsRouter), '",');
        console.log('    "LiquidationEngine": "', address(liquidationEngine), '"');
        console.log('  }');
        console.log('}');
    }
    
    // Helper functions for post-deployment testing
    function verifyDeployment() external view returns (bool) {
        // Basic deployment verification
        require(address(mockUSDC) != address(0), "MockUSDC not deployed");
        require(address(marginAccount) != address(0), "MarginAccount not deployed");
        require(address(insuranceFund) != address(0), "InsuranceFund not deployed");
        require(address(fundingOracle) != address(0), "FundingOracle not deployed");
        require(address(positionManager) != address(0), "PositionManager not deployed");
        require(address(perpsHook) != address(0), "PerpsHook not deployed");
        require(address(perpsRouter) != address(0), "PerpsRouter not deployed");
        require(address(liquidationEngine) != address(0), "LiquidationEngine not deployed");
        
        // Verify balances
        require(insuranceFund.getBalance() >= INITIAL_INSURANCE_FUND, "InsuranceFund not properly funded");
        
        return true;
    }
}
