// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {PositionLib} from "../src/libraries/PositionLib.sol";
import {PositionFactory} from "../src/PositionFactory.sol";
import {PositionNFT} from "../src/PositionNFT.sol";
import {MarketManager} from "../src/MarketManager.sol";
import {PositionManager} from "../src/PositionManagerV2.sol";
import {MarginAccount} from "../src/MarginAccount.sol";
import {MockUSDC} from "../test/utils/mocks/MockUSDC.sol";

/// @title DeployModularPositionSystem - Deploy the new modular position system
/// @notice Deploys and configures all components of the modular architecture
contract DeployModularPositionSystem is Script {
    // Contract instances
    MockUSDC public usdc;
    MarginAccount public marginAccount;
    PositionFactory public positionFactory;
    PositionNFT public positionNFT;
    MarketManager public marketManager;
    PositionManager public positionManager;

    // Test market constants
    bytes32 public constant ETH_USDC_MARKET = keccak256("ETH/USDC");
    
    function run() public {
        vm.startBroadcast();
        
        console.log("=== Deploying Modular Position System ===");
        
        // 1. Deploy base dependencies
        deployBaseDependencies();
        
        // 2. Deploy modular components
        deployModularComponents();
        
        // 3. Configure relationships
        configureRelationships();
        
        // 4. Setup test market
        setupTestMarket();
        
        // 5. Verify deployment
        verifyDeployment();
        
        vm.stopBroadcast();
        
        logDeploymentInfo();
    }

    function deployBaseDependencies() internal {
        console.log("Deploying base dependencies...");
        
        // Deploy USDC mock
        usdc = new MockUSDC();
        console.log("MockUSDC deployed at:", address(usdc));
        
        // Deploy MarginAccount
        marginAccount = new MarginAccount(address(usdc));
        console.log("MarginAccount deployed at:", address(marginAccount));
    }

    function deployModularComponents() internal {
        console.log("Deploying modular components...");
        
        // Deploy PositionFactory
        positionFactory = new PositionFactory(address(usdc), address(marginAccount));
        console.log("PositionFactory deployed at:", address(positionFactory));
        
        // Deploy PositionNFT
        positionNFT = new PositionNFT();
        console.log("PositionNFT deployed at:", address(positionNFT));
        
        // Deploy MarketManager
        marketManager = new MarketManager();
        console.log("MarketManager deployed at:", address(marketManager));
        
        // Deploy PositionManager (orchestrator)
        positionManager = new PositionManager(
            address(positionFactory),
            address(positionNFT),
            address(marketManager)
        );
        console.log("PositionManager deployed at:", address(positionManager));
    }

    function configureRelationships() internal {
        console.log("Configuring component relationships...");
        
        // Set PositionNFT factory
        positionNFT.setFactory(address(positionFactory));
        
        // Set PositionFactory NFT reference
        positionFactory.setPositionNFT(address(positionNFT));
        
        // Configure MarginAccount authorizations
        marginAccount.addAuthorizedContract(address(positionFactory));
        
        // Transfer MarketManager ownership to PositionManager so it can manage markets
        marketManager.transferOwnership(address(positionManager));
        
        // Transfer PositionFactory ownership to PositionManager so it can manage markets
        positionFactory.transferOwnership(address(positionManager));
        
        console.log("Relationships configured successfully");
    }

    function setupTestMarket() internal {
        console.log("Setting up test market...");
        
        // Add ETH/USDC market to both MarketManager and PositionFactory
        address ethToken = address(0x1); // Mock ETH address
        address poolAddress = address(0x2); // Mock pool address
        
        positionManager.addMarket(
            ETH_USDC_MARKET,
            ethToken,
            address(usdc),
            poolAddress
        );
        
        console.log("Test market ETH/USDC added successfully");
    }

    function verifyDeployment() internal view {
        console.log("Verifying deployment...");
        
        // Verify contract sizes are under EIP-170 limit
        uint256 factorySize = address(positionFactory).code.length;
        uint256 nftSize = address(positionNFT).code.length;
        uint256 marketManagerSize = address(marketManager).code.length;
        uint256 orchestratorSize = address(positionManager).code.length;
        
        require(factorySize < 24576, "PositionFactory exceeds size limit");
        require(nftSize < 24576, "PositionNFT exceeds size limit");
        require(marketManagerSize < 24576, "MarketManager exceeds size limit");
        require(orchestratorSize < 24576, "PositionManager exceeds size limit");
        
        // Verify NFT factory is set
        require(positionNFT.factory() == address(positionFactory), "NFT factory not set");
        
        // Verify margin account authorization
        require(marginAccount.authorized(address(positionFactory)), "Factory not authorized");
        
        // Verify market exists
        PositionLib.Market memory market = positionManager.getMarket(ETH_USDC_MARKET);
        require(market.baseAsset != address(0), "Test market not found");
        
        console.log("All verifications passed!");
    }

    function logDeploymentInfo() internal view {
        console.log("\n=== Deployment Summary ===");
        console.log("MockUSDC:", address(usdc));
        console.log("MarginAccount:", address(marginAccount));
        console.log("PositionFactory:", address(positionFactory));
        console.log("PositionNFT:", address(positionNFT));
        console.log("MarketManager:", address(marketManager));
        console.log("PositionManager:", address(positionManager));
        
        console.log("\n=== Contract Sizes ===");
        console.log("PositionFactory:", address(positionFactory).code.length, "bytes");
        console.log("PositionNFT:", address(positionNFT).code.length, "bytes");
        console.log("MarketManager:", address(marketManager).code.length, "bytes");
        console.log("PositionManager:", address(positionManager).code.length, "bytes");
        
        console.log("\n=== Test Market ===");
        console.log("ETH/USDC Market ID:", vm.toString(abi.encodePacked(ETH_USDC_MARKET)));
        
        console.log("\nModular position system deployed successfully!");
    }
}
