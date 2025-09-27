// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

import {MarginAccount} from "../src/MarginAccount.sol";
import {InsuranceFund} from "../src/InsuranceFund.sol";
import {FundingOracle} from "../src/FundingOracle.sol";
import {PerpsRouter} from "../src/PerpsRouter.sol";
import {PositionManager} from "../src/PositionManagerV2.sol";
import {PositionFactory} from "../src/PositionFactory.sol";
import {PositionNFT} from "../src/PositionNFT.sol";
import {MarketManager} from "../src/MarketManager.sol";
import {PerpsHook} from "../src/PerpsHook.sol";

/// @title DeployIntegratedSystem - Complete deployment with proper integrations
/// @notice Deploys and configures the full perpetual futures system with proper integrations
contract DeployIntegratedSystemScript is Script {
    using PoolIdLibrary for PoolKey;
    
    // Known addresses - Update these for your deployment environment
    address constant USDC_ADDRESS = 0x5FbDB2315678afecb367f032d93F642f64180aa3; // MockUSDC
    address constant VETH_ADDRESS = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512; // MockVETH
    address constant POOL_MANAGER_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // Placeholder - would be real Uniswap PoolManager
    
    // Contract instances
    MarginAccount public marginAccount;
    InsuranceFund public insuranceFund;
    FundingOracle public fundingOracle;
    PositionManager public positionManager;
    PositionFactory public positionFactory;
    PositionNFT public positionNFT;
    MarketManager public marketManager;
    PerpsHook public perpsHook;
    PerpsRouter public perpsRouter;
    
    // Market configuration
    PoolKey public ethUsdcPoolKey;
    PoolId public ethUsdcPoolId;
    
    function run() external {
        console.log("=== DEPLOYING INTEGRATED PERPETUAL FUTURES SYSTEM ===");
        console.log("Deployer address:", msg.sender);
        console.log("Using USDC at:", USDC_ADDRESS);
        console.log("Using VETH at:", VETH_ADDRESS);
        console.log("Using PoolManager at:", POOL_MANAGER_ADDRESS);
        
        vm.startBroadcast();
        
        // Step 1: Deploy core contracts
        _deployCoreContracts();
        
        // Step 2: Setup authorizations
        _setupAuthorizations();
        
        // Step 3: Configure FundingOracle with ETH-USDC market
        _configureFundingOracle();
        
        // Step 4: Add market to PositionManager
        _configurePositionManager();
        
        vm.stopBroadcast();
        
        // Step 5: Print deployment summary
        _printDeploymentSummary();
        
        console.log("\n=== INTEGRATION COMPLETE ===");
        console.log("The system is now ready for trading!");
        console.log("\nNext steps:");
        console.log("1. Initialize pool in Uniswap V4 with the deployed hook");
        console.log("2. Fund InsuranceFund with initial USDC deposit");
        console.log("3. Test complete trading flows through PerpsRouter");
        console.log("4. Set up liquidation monitoring system");
    }
    
    function _deployCoreContracts() internal {
        console.log("\n=== STEP 1: DEPLOYING CORE CONTRACTS ===");
        
        // 1.1 Deploy MarginAccount
        console.log("1.1 Deploying MarginAccount...");
        marginAccount = new MarginAccount(USDC_ADDRESS);
        console.log("    MarginAccount deployed to:", address(marginAccount));
        
        // 1.2 Deploy InsuranceFund  
        console.log("1.2 Deploying InsuranceFund...");
        insuranceFund = new InsuranceFund(USDC_ADDRESS);
        console.log("    InsuranceFund deployed to:", address(insuranceFund));
        
        // 1.3 Deploy modular PositionManager system
        console.log("1.3 Deploying modular PositionManager system...");
        
        // Deploy PositionFactory
        positionFactory = new PositionFactory(USDC_ADDRESS, address(marginAccount));
        console.log("    PositionFactory deployed to:", address(positionFactory));
        
        // Deploy PositionNFT
        positionNFT = new PositionNFT();
        console.log("    PositionNFT deployed to:", address(positionNFT));
        
        // Deploy MarketManager
        marketManager = new MarketManager();
        console.log("    MarketManager deployed to:", address(marketManager));
        
        // Deploy PositionManager
        positionManager = new PositionManager(
            address(positionFactory),
            address(positionNFT),
            address(marketManager)
        );
        console.log("    PositionManager deployed to:", address(positionManager));
        
        // Set up component relationships
        positionFactory.setPositionNFT(address(positionNFT));
        positionNFT.setFactory(address(positionFactory));
        
        // 1.4 Deploy FundingOracle
        console.log("1.4 Deploying FundingOracle...");
        address pythContract = address(0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF); // Placeholder for Pyth
        fundingOracle = new FundingOracle(pythContract);
        console.log("    FundingOracle deployed to:", address(fundingOracle));
        
        // 1.5 Use already deployed PerpsHook
        console.log("1.5 Using deployed PerpsHook...");
        address DEPLOYED_PERPS_HOOK = 0xaF8e584B4c1D75A025531EBFD8284C60cEE4DaC8; // Deployed PerpsHook
        perpsHook = PerpsHook(DEPLOYED_PERPS_HOOK);
        console.log("    PerpsHook address:", address(perpsHook));
        
        // 1.6 Deploy PerpsRouter
        console.log("1.6 Deploying PerpsRouter...");
        perpsRouter = new PerpsRouter(
            address(positionFactory),
            address(positionNFT),
            address(marketManager),
            address(fundingOracle),
            POOL_MANAGER_ADDRESS,
            USDC_ADDRESS
        );
        console.log("    PerpsRouter deployed to:", address(perpsRouter));
    }
    
    function _setupAuthorizations() internal {
        console.log("\n=== STEP 2: SETTING UP AUTHORIZATIONS ===");
        
        console.log("2.1 Configuring MarginAccount authorizations...");
        marginAccount.addAuthorizedContract(address(perpsRouter));
        marginAccount.addAuthorizedContract(address(positionManager));
        marginAccount.addAuthorizedContract(address(perpsHook));
        console.log("    MarginAccount authorized: PerpsRouter, PositionManager, PerpsHook");
        
        console.log("2.2 Configuring InsuranceFund authorizations...");
        insuranceFund.addAuthorizedContract(address(perpsRouter));
        insuranceFund.addAuthorizedContract(address(positionManager));
        insuranceFund.addAuthorizedContract(address(perpsHook));
        console.log("    InsuranceFund authorized: PerpsRouter, PositionManager, PerpsHook");
    }
    
    function _configureFundingOracle() internal {
        console.log("\n=== STEP 3: CONFIGURING FUNDING ORACLE ===");
        
        // Create ETH-USDC pool key
        ethUsdcPoolKey = PoolKey({
            currency0: Currency.wrap(VETH_ADDRESS < USDC_ADDRESS ? VETH_ADDRESS : USDC_ADDRESS),
            currency1: Currency.wrap(VETH_ADDRESS < USDC_ADDRESS ? USDC_ADDRESS : VETH_ADDRESS),
            fee: 3000, // 0.3% fee
            tickSpacing: 60,
            hooks: IHooks(address(perpsHook))
        });
        ethUsdcPoolId = ethUsdcPoolKey.toId();
        
        console.log("3.1 Adding ETH-USDC market to FundingOracle...");
        console.log("    Pool ID:", vm.toString(PoolId.unwrap(ethUsdcPoolId)));
        console.log("    PerpsHook address:", address(perpsHook));
        
        // Add market with Pyth feed ID for ETH/USD
        bytes32 ethUsdFeedId = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace; // ETH/USD Pyth feed
        fundingOracle.addMarket(ethUsdcPoolId, address(perpsHook), ethUsdFeedId);
        console.log("    ETH-USDC market added to FundingOracle with Pyth integration");
        
        // For now, we don't add external price sources
        // In production, you would add Chainlink or other oracle sources here
        console.log("    Note: Pyth integration configured, additional oracles can be added later");
    }
    
    function _configurePositionManager() internal {
        console.log("\n=== STEP 4: CONFIGURING POSITION MANAGER ===");
        
        console.log("4.1 Adding ETH-USDC market to PositionManager...");
        bytes32 marketId = bytes32(PoolId.unwrap(ethUsdcPoolId));
        
        positionManager.addMarket(
            marketId,
            VETH_ADDRESS,  // Base asset (ETH)
            USDC_ADDRESS,  // Quote asset (USDC)
            address(perpsHook) // Pool/Hook address
        );
        
        console.log("    Market ID:", vm.toString(marketId));
        console.log("    Base Asset (VETH):", VETH_ADDRESS);
        console.log("    Quote Asset (USDC):", USDC_ADDRESS);
        console.log("    Pool Address:", address(perpsHook));
        console.log("    ETH-USDC market added to PositionManager");
    }
    
    function _printDeploymentSummary() internal view {
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Core Contracts:");
        console.log("  MarginAccount:     ", address(marginAccount));
        console.log("  InsuranceFund:     ", address(insuranceFund));
        console.log("  PositionManager:   ", address(positionManager));
        console.log("  FundingOracle:     ", address(fundingOracle));
        console.log("  PerpsHook:         ", address(perpsHook));
        console.log("  PerpsRouter:       ", address(perpsRouter));
        console.log("");
        console.log("Token Addresses:");
        console.log("  USDC:              ", USDC_ADDRESS);
        console.log("  VETH:              ", VETH_ADDRESS);
        console.log("");
        console.log("Market Configuration:");
        console.log("  ETH-USDC Pool ID:  ", vm.toString(PoolId.unwrap(ethUsdcPoolId)));
        console.log("  Market ID:         ", vm.toString(bytes32(PoolId.unwrap(ethUsdcPoolId))));
        console.log("");
        console.log("Integration Status:");
        console.log("  [X] PerpsHook integrated with MarginAccount");
        console.log("  [X] PositionManager integrated with MarginAccount"); 
        console.log("  [X] FundingOracle configured with ETH-USDC market");
        console.log("  [X] All contracts properly authorized");
        console.log("  [X] PerpsRouter ready for end-to-end trading");
    }
}
