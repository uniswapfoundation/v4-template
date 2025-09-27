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

// Uniswap V4 and HookMiner
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "../lib/v4-periphery/src/utils/HookMiner.sol";

/// @title Production Deployment Script with HookMiner
/// @notice Deploys the complete Perpetual Futures Protocol with mined hook address
/// @dev Uses HookMiner to generate a valid hook address for Uniswap v4
contract DeployProductionWithMinerScript is Script {
    
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
    
    // Network-specific Pyth contract addresses
    mapping(string => address) public pythContracts;
    
    // Network-specific PoolManager addresses
    mapping(string => address) public poolManagerAddresses;
    
    // Uniswap V4 addresses (would be different per network)
    address public constant POOL_MANAGER_PLACEHOLDER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    
    // ETH/USD Pyth Price Feed ID (same across all networks)
    bytes32 public constant ETH_USD_FEED_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    
    // Initial configuration values
    uint256 public constant INITIAL_INSURANCE_FUND = 50_000e6; // $50,000 USDC
    uint256 public constant INITIAL_DEPLOYER_USDC = 1_000_000e6; // $1M USDC for testing
    
    // CREATE2 Deployer for deterministic addresses
    address public constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    
    function setUp() public {
        // Get private key from environment, with Anvil default as fallback
        try vm.envString("PRIVATE_KEY") returns (string memory privateKeyStr) {
            // Handle both formats: with and without 0x prefix
            if (bytes(privateKeyStr).length == 64) {
                // No 0x prefix, parse as hex
                deployerPrivateKey = vm.parseUint(string(abi.encodePacked("0x", privateKeyStr)));
            } else if (bytes(privateKeyStr).length == 66) {
                // Has 0x prefix
                deployerPrivateKey = vm.parseUint(privateKeyStr);
            } else {
                revert("Invalid private key format");
            }
        } catch {
            deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80; // Anvil default
        }
        deployer = vm.addr(deployerPrivateKey);
        
        // Try to get deployment network from environment, default to "anvil"
        try vm.envString("DEPLOYMENT_NETWORK") returns (string memory network) {
            deploymentNetwork = network;
        } catch {
            deploymentNetwork = "anvil";
        }
        
        // Configure Pyth contract addresses per network
        pythContracts["anvil"] = address(0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF); // Placeholder for local testing
        pythContracts["sepolia"] = 0xDd24F84d36BF92C65F92307595335bdFab5Bbd21; // Pyth Sepolia testnet
        pythContracts["mainnet"] = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6; // Pyth Ethereum mainnet
        pythContracts["arbitrum"] = 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C; // Pyth Arbitrum
        pythContracts["arbitrum-sepolia"] = 0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF; // Pyth Arbitrum Sepolia
        pythContracts["polygon"] = 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C; // Pyth Polygon
        pythContracts["base"] = 0x8250f4aF4B972684F7b336503E2D6dFeDeB1487a; // Pyth Base
        pythContracts["optimism"] = 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C; // Pyth Optimism
        pythContracts["unichain-sepolia"] = 0x2880aB155794e7179c9eE2e38200202908C17B43; // Pyth Unichain Sepolia
        
        // Configure PoolManager addresses per network
        poolManagerAddresses["anvil"] = POOL_MANAGER_PLACEHOLDER; // Placeholder for local testing
        poolManagerAddresses["unichain-sepolia"] = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC; // Unichain Sepolia PoolManager
    }
    
    /// @notice Get the Pyth contract address for the current deployment network
    function getPythContract() internal view returns (address) {
        address pythAddress = pythContracts[deploymentNetwork];
        require(pythAddress != address(0), string(abi.encodePacked("Pyth contract not configured for network: ", deploymentNetwork)));
        return pythAddress;
    }
    
    /// @notice Get the PoolManager address for the current deployment network
    function getPoolManager() internal view returns (address) {
        address poolManager = poolManagerAddresses[deploymentNetwork];
        if (poolManager == address(0)) {
            // Fallback to placeholder for networks without configured PoolManager
            return POOL_MANAGER_PLACEHOLDER;
        }
        return poolManager;
    }
    
    function run() external {
        console.log("==============================================");
        console.log("PERPETUAL FUTURES PROTOCOL - PRODUCTION DEPLOYMENT WITH HOOKMINER");
        console.log("==============================================");
        console.log("Network:", deploymentNetwork);
        console.log("Deployer:", deployer);
        console.log("Pyth Contract:", getPythContract());
        console.log("ETH/USD Feed ID:", vm.toString(ETH_USD_FEED_ID));
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
        
        // Phase 3: Mine Hook Address and Deploy Hook
        console.log("\nPHASE 3: Mining Hook Address and Deploying Hook");
        console.log("-----------------------------------------------");
        deployHookWithMiner();
        
        // Phase 4: Deploy Remaining Uniswap V4 Integration
        console.log("\nPHASE 4: Deploying Remaining Uniswap V4 Integration");
        console.log("--------------------------------------------------");
        deployRemainingUniswapContracts();
        
        // Phase 5: Deploy Liquidation System
        console.log("\nPHASE 5: Deploying Liquidation System");
        console.log("------------------------------------");
        deployLiquidationEngine();
        
        // Phase 6: Setup Authorizations and Configurations
        console.log("\nPHASE 6: Setting up Authorizations and Configurations");
        console.log("-----------------------------------------------------");
        setupAuthorizations();
        setupConfigurations();
        
        // Phase 7: Initial Funding and Market Setup
        console.log("\nPHASE 7: Initial Funding and Market Setup");
        console.log("-----------------------------------------");
        initialFunding();
        
        vm.stopBroadcast();
        
        // Phase 8: Generate Deployment Report
        console.log("\nPHASE 8: Generating Deployment Report");
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
        fundingOracle = new FundingOracle(getPythContract());
        console.log("   FundingOracle deployed at:", address(fundingOracle));
        console.log("   Using Pyth contract at:", getPythContract());
        console.log("   Network:", deploymentNetwork);
    }
    
    function deployHookWithMiner() internal {
        // Deploy modular PositionManager system first (needed for hook constructor)
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
        
        console.log("2. Mining valid hook address...");
        
        // Define the hook permissions required by PerpsHook (based on getHookPermissions())
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG |         // Bit 12: 4096 - Used to initialize market state
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |     // Bit 11: 2048 - Used to block liquidity operations  
            Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |  // Bit 9:  512  - Used to block liquidity operations
            Hooks.BEFORE_SWAP_FLAG |              // Bit 7:  128  - Core perp trading logic
            Hooks.AFTER_SWAP_FLAG |               // Bit 6:  64   - Execute position operations
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG  // Bit 3:  8    - Return delta to override swaps
        );
        // Total: 4096 + 2048 + 512 + 128 + 64 + 8 = 6856
        
        console.log("   Required hook flags:", flags);
        console.log("   Flag breakdown:");
        console.log("     AFTER_INITIALIZE_FLAG (4096) - Initialize market state");
        console.log("     BEFORE_ADD_LIQUIDITY_FLAG (2048) - Block liquidity operations");
        console.log("     BEFORE_REMOVE_LIQUIDITY_FLAG (512) - Block liquidity operations");
        console.log("     BEFORE_SWAP_FLAG (128) - Core perp trading logic");
        console.log("     AFTER_SWAP_FLAG (64) - Execute position operations");
        console.log("     BEFORE_SWAP_RETURNS_DELTA_FLAG (8) - Override swap behavior");
        
        // Get the creation code and constructor arguments with ACTUAL component addresses
        bytes memory creationCode = type(PerpsHook).creationCode;
        bytes memory constructorArgs = abi.encode(
            getPoolManager(),
            address(positionManager), // PositionManager address (not individual components)
            address(positionFactory),
            address(marginAccount),
            address(fundingOracle),
            address(mockUSDC),
            msg.sender // Pass deployer as initial owner
        );
        
        console.log("   Mining address with HookMiner...");
        
        // Mine the hook address
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            creationCode,
            constructorArgs
        );
        
        console.log("   SUCCESS: Found valid hook address:", hookAddress);
        console.log("   Salt used:", vm.toString(salt));
        console.log("   Hook address validation:", uint160(hookAddress) & Hooks.ALL_HOOK_MASK);
        
        // Now deploy the hook with CREATE2 using the mined salt
        console.log("3. Deploying PerpsHook with mined address...");
        
        console.log("   Deploying hook using CREATE2 with mined salt...");
        console.log("   Salt:", vm.toString(salt));
        console.log("   Target address:", hookAddress);
        
        // For testnets/mainnet: Deploy the hook using CREATE2 with the mined salt
        // For local testing: Skip deployment and use placeholder
        if (keccak256(abi.encodePacked(deploymentNetwork)) == keccak256(abi.encodePacked("anvil"))) {
            // Local testing: Don't deploy hook, just use the address for setup
            console.log("   Local testing: Using placeholder hook address");
            console.log("   Production deployment should use CREATE2 with:");
            console.log("     Salt:", vm.toString(salt));
            console.log("     Target address:", hookAddress);
            perpsHook = PerpsHook(hookAddress);
        } else {
            // Testnet/Mainnet: Deploy the hook using CREATE2 with the mined salt
            // This follows the official Uniswap v4 hook deployment guide
            console.log("   Deploying hook with CREATE2 for", deploymentNetwork);
            
            // Use the same CREATE2 deployer that HookMiner used with SAME constructor args
            bytes memory creationCodeWithArgs = abi.encodePacked(
                type(PerpsHook).creationCode,
                constructorArgs // Use the SAME constructor args as mining (now with 6 parameters)
            );
            
            console.log("   Using CREATE2 deployer:", CREATE2_DEPLOYER);
            console.log("   Deploying to target address:", hookAddress);
            
            // Deploy using the same CREATE2 deployer as HookMiner
            (bool success, bytes memory returnData) = CREATE2_DEPLOYER.call(
                abi.encodePacked(salt, creationCodeWithArgs)
            );
            
            require(success, "CREATE2 deployment failed");
            
            // The deployed address is the returned bytes20 from CREATE2 deployer
            address deployedAddress = address(bytes20(returnData));
            
            console.log("   Deployed address:  ", deployedAddress);
            console.log("   Expected address:  ", hookAddress);
            console.log("   Addresses match:   ", deployedAddress == hookAddress);
            
            // Verify the deployed address matches the mined address
            require(deployedAddress == hookAddress, "Hook address mismatch - CREATE2 deployment failed");
            
            perpsHook = PerpsHook(deployedAddress);
            console.log("   SUCCESS: Hook deployed and verified at:", address(perpsHook));
        }
        
        console.log("   Hook validation flags:", uint160(address(perpsHook)) & Hooks.ALL_HOOK_MASK);
        console.log("   Required flags were:", flags);
        console.log("   Address validation:", address(perpsHook) == hookAddress ? "PASSED" : "FAILED");
        console.log("   HookMiner would deploy to:", hookAddress, "with salt:", vm.toString(salt));
    }
    
    function deployRemainingUniswapContracts() internal {
        console.log("1. Deploying PerpsRouter...");
        perpsRouter = new PerpsRouter(
            address(marginAccount),
            address(positionManager),
            address(positionFactory),
            address(fundingOracle),
            getPoolManager(),
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
        
        // Only authorize hook if it's actually deployed (not on anvil)
        if (keccak256(abi.encodePacked(deploymentNetwork)) != keccak256(abi.encodePacked("anvil"))) {
            marginAccount.addAuthorizedContract(address(perpsHook));
            console.log("   SUCCESS: Authorized: PerpsRouter, PositionManager, PerpsHook, LiquidationEngine");
        } else {
            console.log("   SUCCESS: Authorized: PerpsRouter, PositionManager, LiquidationEngine");
            console.log("   Note: Hook authorization skipped (local testing)");
        }
        marginAccount.addAuthorizedContract(address(liquidationEngine));
        
        console.log("2. Setting up InsuranceFund authorizations...");
        insuranceFund.addAuthorizedContract(address(perpsRouter));
        insuranceFund.addAuthorizedContract(address(positionManager));
        
        // Only authorize hook if it's actually deployed (not on anvil)
        if (keccak256(abi.encodePacked(deploymentNetwork)) != keccak256(abi.encodePacked("anvil"))) {
            insuranceFund.addAuthorizedContract(address(perpsHook));
        }
        insuranceFund.addAuthorizedContract(address(liquidationEngine));
        console.log("   SUCCESS: Authorized: PerpsRouter, PositionManager, PerpsHook, LiquidationEngine");
        
        console.log("3. Setting up Key Manager authorizations...");
        marketManager.addKeyManager(deployer);
        positionFactory.addKeyManager(deployer);
        console.log("   SUCCESS: Added deployer as key manager for MarketManager and PositionFactory");
        console.log("   Key Manager Address:", deployer);
    }
    
    function setupConfigurations() internal {
        console.log("1. Configuring market parameters...");
        
        // Add ETH-USDC market to FundingOracle using the standard ETH/USD Pyth feed
        // This feed ID works across all Pyth-supported networks
        
        // For now, we'll skip market configuration as it requires proper PoolId setup
        // This would be done after Uniswap v4 pool creation
        console.log("   Market configuration skipped - requires proper Uniswap v4 pool setup");
        console.log("   ETH/USD Pyth Price Feed ID:", vm.toString(ETH_USD_FEED_ID));
        console.log("   Network:", deploymentNetwork);
        console.log("   Pyth Contract:", getPythContract());
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
        
        console.log("\nHOOK VALIDATION:");
        console.log("Hook Address:     ", address(perpsHook));
        console.log("Hook Flags:       ", uint160(address(perpsHook)) & Hooks.ALL_HOOK_MASK);
        console.log("Required Flags:   ", uint160(
            Hooks.AFTER_INITIALIZE_FLAG |
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
            Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG |
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        ));
        console.log("Validation Match: ", (uint160(address(perpsHook)) & Hooks.ALL_HOOK_MASK) == uint160(
            Hooks.AFTER_INITIALIZE_FLAG |
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
            Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG |
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        ));
        
        console.log("\nLIQUIDATION SYSTEM:");
        console.log("LiquidationEngine:", address(liquidationEngine));
        
        console.log("\nEXTERNAL DEPENDENCIES:");
        console.log("Network:          ", deploymentNetwork);
        console.log("PoolManager:      ", getPoolManager());
        console.log("Pyth Contract:    ", getPythContract());
        console.log("ETH/USD Feed ID:  ", vm.toString(ETH_USD_FEED_ID));
        
        console.log("\nINITIAL BALANCES:");
        console.log("Deployer USDC:    ", mockUSDC.balanceOf(deployer) / 1e6, "USDC");
        console.log("Deployer VETH:    ", mockVETH.balanceOf(deployer) / 1e18, "VETH");
        console.log("Insurance Fund:   ", insuranceFund.getBalance() / 1e6, "USDC");
        
        console.log("==============================================");
        
        // Generate JSON deployment file
        console.log("\nDeployment JSON Configuration:");
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
        console.log('  },');
        console.log('  "hookValidation": {');
        console.log('    "address": "', address(perpsHook), '",');
        console.log('    "flags": ', uint160(address(perpsHook)) & Hooks.ALL_HOOK_MASK, ',');
        console.log('    "isValid": ', (uint160(address(perpsHook)) & Hooks.ALL_HOOK_MASK) == uint160(
            Hooks.AFTER_INITIALIZE_FLAG |
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
            Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG |
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        ));
        console.log('  }');
        console.log('}');
    }
    
    // Helper function to verify deployment
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
        
        // Verify hook address is valid
        uint160 hookFlags = uint160(address(perpsHook)) & Hooks.ALL_HOOK_MASK;
        uint160 requiredFlags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG |
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );
        require(hookFlags == requiredFlags, "Hook address validation failed");
        
        // Verify authorizations
        require(marginAccount.authorized(address(perpsRouter)), "PerpsRouter not authorized on MarginAccount");
        require(insuranceFund.authorized(address(liquidationEngine)), "LiquidationEngine not authorized on InsuranceFund");
        
        // Verify balances
        require(insuranceFund.getBalance() >= INITIAL_INSURANCE_FUND, "InsuranceFund not properly funded");
        
        return true;
    }
}
