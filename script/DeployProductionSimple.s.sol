// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

// Core contracts
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

// Uniswap imports
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

/// @title Simple Production Deployment Script
/// @notice Deploys the complete Perpetual Futures Protocol with MockUSDC
contract DeployProductionSimpleScript is Script {
    
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
    
    // Placeholder addresses
    address public constant POOL_MANAGER_PLACEHOLDER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public constant PYTH_PLACEHOLDER = 0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF;
    
    // Initial values
    uint256 public constant INITIAL_INSURANCE_FUND = 50_000e6; // $50,000 USDC
    uint256 public constant INITIAL_DEPLOYER_USDC = 1_000_000e6; // $1M USDC for testing
    
    function run() external {
        deployer = msg.sender;
        
        console.log("==============================================");
        console.log("PERPETUAL FUTURES PROTOCOL - PRODUCTION DEPLOYMENT");
        console.log("==============================================");
        console.log("Deployer:", deployer);
        console.log("==============================================\n");
        
        vm.startBroadcast();
        
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
        
        // Phase 5: Setup Authorizations
        console.log("\nPHASE 5: Setting up Authorizations");
        console.log("----------------------------------");
        setupAuthorizations();
        
        // Phase 6: Initial Funding
        console.log("\nPHASE 6: Initial Funding");
        console.log("------------------------");
        initialFunding();
        
        vm.stopBroadcast();
        
        // Phase 7: Generate Deployment Report
        console.log("\nPHASE 7: Deployment Report");
        console.log("--------------------------");
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
        fundingOracle = new FundingOracle(PYTH_PLACEHOLDER);
        console.log("   FundingOracle deployed at:", address(fundingOracle));
        console.log("   Using Pyth contract at:", PYTH_PLACEHOLDER);
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
            IPoolManager(POOL_MANAGER_PLACEHOLDER),
            positionManager,
            positionFactory,
            marginAccount,
            fundingOracle,
            mockUSDC,
            msg.sender // Initial owner
        );
        console.log("   PerpsHook deployed at:", address(perpsHook));
        
        console.log("3. Deploying PerpsRouter...");
        perpsRouter = new PerpsRouter(
            address(marginAccount),
            address(positionManager),
            address(positionFactory),
            address(fundingOracle),
            POOL_MANAGER_PLACEHOLDER,
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
    
    function initialFunding() internal {
        console.log("1. Funding InsuranceFund with initial capital...");
        
        // Approve and deposit to insurance fund
        mockUSDC.approve(address(insuranceFund), INITIAL_INSURANCE_FUND);
        insuranceFund.deposit(INITIAL_INSURANCE_FUND);
        
        console.log("   SUCCESS: InsuranceFund funded with:", INITIAL_INSURANCE_FUND / 1e6, "USDC");
        console.log("   Insurance Fund Balance:", insuranceFund.getBalance() / 1e6, "USDC");
    }
    
    function generateDeploymentReport() internal view {
        console.log("Network: Local Anvil");
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
        console.log("PoolManager:      ", POOL_MANAGER_PLACEHOLDER);
        console.log("Pyth Contract:    ", PYTH_PLACEHOLDER);
        
        console.log("\nINITIAL BALANCES:");
        console.log("Deployer USDC:    ", mockUSDC.balanceOf(deployer) / 1e6, "USDC");
        console.log("Deployer VETH:    ", mockVETH.balanceOf(deployer) / 1e18, "VETH");
        console.log("Insurance Fund:   ", insuranceFund.getBalance() / 1e6, "USDC");
        
        console.log("\n==============================================");
        console.log("JSON DEPLOYMENT CONFIG:");
        console.log("==============================================");
        console.log("{");
        console.log('  "network": "anvil",');
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
        console.log("==============================================");
    }
}
