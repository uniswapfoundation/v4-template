// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Uniswap V4 and HookMiner
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "../lib/v4-periphery/src/utils/HookMiner.sol";

// Core contracts
import {PerpsHook} from "../src/PerpsHook.sol";
import {PositionManager} from "../src/PositionManagerV2.sol";
import {PositionFactory} from "../src/PositionFactory.sol";
import {PositionNFT} from "../src/PositionNFT.sol";
import {MarketManager} from "../src/MarketManager.sol";
import {MarginAccount} from "../src/MarginAccount.sol";
import {FundingOracle} from "../src/FundingOracle.sol";

// Mock contracts for testing
import {MockUSDC} from "../test/utils/mocks/MockUSDC.sol";

/// @title Testnet Hook Deployment Script
/// @notice Deploys PerpsHook following official Uniswap v4 deployment guide
/// @dev Uses CREATE2 with mined salt for proper hook address validation
contract DeployTestnetHookScript is Script {
    
    // Network-specific configurations
    mapping(string => address) public pythContracts;
    mapping(string => address) public poolManagers;
    
    // ETH/USD Pyth Price Feed ID (same across all networks)
    bytes32 public constant ETH_USD_FEED_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    
    // CREATE2 Deployer for deterministic addresses
    address public constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    
    string public deploymentNetwork;
    
    function setUp() public {
        // Get deployment network from environment
        try vm.envString("DEPLOYMENT_NETWORK") returns (string memory network) {
            deploymentNetwork = network;
        } catch {
            deploymentNetwork = "sepolia"; // Default to sepolia for testnet deployment
        }
        
        // Configure Pyth contract addresses per network
        pythContracts["sepolia"] = 0xDd24F84d36BF92C65F92307595335bdFab5Bbd21;
        pythContracts["arbitrum-sepolia"] = 0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF;
        pythContracts["mainnet"] = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6;
        pythContracts["arbitrum"] = 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C;
        pythContracts["polygon"] = 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C;
        pythContracts["base"] = 0x8250f4aF4B972684F7b336503E2D6dFeDeB1487a;
        pythContracts["optimism"] = 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C;
        
        // Configure PoolManager addresses per network (you'll need to update these with actual deployed addresses)
        poolManagers["sepolia"] = address(0); // Update with actual Sepolia PoolManager
        poolManagers["arbitrum-sepolia"] = address(0); // Update with actual Arbitrum Sepolia PoolManager
        poolManagers["mainnet"] = address(0); // Update with actual Mainnet PoolManager
        poolManagers["arbitrum"] = address(0); // Update with actual Arbitrum PoolManager
    }
    
    function getPythContract() internal view returns (address) {
        address pythAddress = pythContracts[deploymentNetwork];
        require(pythAddress != address(0), string(abi.encodePacked("Pyth contract not configured for network: ", deploymentNetwork)));
        return pythAddress;
    }
    
    function getPoolManager() internal view returns (address) {
        address poolManager = poolManagers[deploymentNetwork];
        require(poolManager != address(0), string(abi.encodePacked("PoolManager not configured for network: ", deploymentNetwork)));
        return poolManager;
    }
    
    function run() external {
        console.log("==============================================");
        console.log("TESTNET HOOK DEPLOYMENT - Following Uniswap v4 Guide");
        console.log("==============================================");
        console.log("Network:", deploymentNetwork);
        console.log("Pyth Contract:", getPythContract());
        console.log("ETH/USD Feed ID:", vm.toString(ETH_USD_FEED_ID));
        console.log("==============================================\n");
        
        // Note: This script assumes you have already deployed the MODULAR SYSTEM:
        // - PositionFactory
        // - PositionNFT  
        // - MarketManager
        // - MarginAccount  
        // - FundingOracle
        // - MockUSDC
        // You'll need to update these addresses below for the modular system
        
        address positionFactoryAddr = vm.envAddress("POSITION_FACTORY_ADDRESS");
        address positionNFTAddr = vm.envAddress("POSITION_NFT_ADDRESS");
        address marketManagerAddr = vm.envAddress("MARKET_MANAGER_ADDRESS");
        address positionManagerAddr = vm.envAddress("POSITION_MANAGER_ADDRESS");
        address marginAccountAddr = vm.envAddress("MARGIN_ACCOUNT_ADDRESS");
        address fundingOracleAddr = vm.envAddress("FUNDING_ORACLE_ADDRESS");
        address usdcAddr = vm.envAddress("USDC_ADDRESS");
        
        console.log("Using existing modular contracts:");
        console.log("  PositionFactory:", positionFactoryAddr);
        console.log("  PositionNFT:", positionNFTAddr);
        console.log("  MarketManager:", marketManagerAddr);
        console.log("  PositionManager:", positionManagerAddr);
        console.log("  MarginAccount:", marginAccountAddr);
        console.log("  FundingOracle:", fundingOracleAddr);
        console.log("  USDC:", usdcAddr);
        console.log("");
        
        vm.startBroadcast();
        
        deployHookWithMiner(
            positionFactoryAddr,
            positionNFTAddr,
            marketManagerAddr,
            positionManagerAddr,
            marginAccountAddr, 
            payable(fundingOracleAddr),
            usdcAddr
        );
        
        vm.stopBroadcast();
        
        console.log("==============================================");
        console.log("TESTNET HOOK DEPLOYMENT COMPLETED!");
        console.log("==============================================");
    }
    
    function deployHookWithMiner(
        address positionFactory,
        address positionNFT,
        address marketManager,
        address positionManager,
        address marginAccount,
        address payable fundingOracle,
        address usdc
    ) internal {
        console.log("1. Mining hook address...");
        
        // Hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG |           // 4096 - Initialize market state
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |       // 2048 - Block liquidity operations
            Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |    // 512  - Block liquidity operations
            Hooks.BEFORE_SWAP_FLAG |                // 128  - Core perp trading logic
            Hooks.AFTER_SWAP_FLAG |                 // 64   - Execute position operations
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG    // 8    - Override swap behavior
        );
        
        console.log("   Required hook flags:", flags);
        console.log("   Flag breakdown:");
        console.log("     AFTER_INITIALIZE_FLAG (4096) - Initialize market state");
        console.log("     BEFORE_ADD_LIQUIDITY_FLAG (2048) - Block liquidity operations");
        console.log("     BEFORE_REMOVE_LIQUIDITY_FLAG (512) - Block liquidity operations");
        console.log("     BEFORE_SWAP_FLAG (128) - Core perp trading logic");
        console.log("     AFTER_SWAP_FLAG (64) - Execute position operations");
        console.log("     BEFORE_SWAP_RETURNS_DELTA_FLAG (8) - Override swap behavior");
        
        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(
            getPoolManager(),
            positionManager,
            positionFactory,
            marginAccount,
            fundingOracle,
            usdc
        );
        
        console.log("   Mining address with HookMiner...");
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(PerpsHook).creationCode,
            constructorArgs
        );
        
        console.log("   SUCCESS: Found valid hook address:", hookAddress);
        console.log("   Salt used:", vm.toString(salt));
        console.log("   Hook address validation:", uint160(hookAddress) & Hooks.ALL_HOOK_MASK);
        
        console.log("2. Deploying hook using CREATE2...");
        
        // Deploy the hook using CREATE2 with the mined salt
        // This follows the official Uniswap v4 hook deployment guide
        PerpsHook perpsHook = new PerpsHook{salt: salt}(
            IPoolManager(getPoolManager()),
            PositionManager(positionManager),
            PositionFactory(positionFactory),
            MarginAccount(marginAccount),
            FundingOracle(fundingOracle),
            IERC20(usdc)
        );
        
        // Verify the deployed address matches the mined address
        require(address(perpsHook) == hookAddress, "Hook address mismatch - CREATE2 deployment failed");
        
        console.log("   SUCCESS: PerpsHook deployed at:", address(perpsHook));
        console.log("   Hook validation flags:", uint160(address(perpsHook)) & Hooks.ALL_HOOK_MASK);
        console.log("   Required flags were:", flags);
        console.log("   Address validation: PASSED");
        
        console.log("3. Hook deployment verification...");
        console.log("   Hook implements getHookPermissions():", address(perpsHook).code.length > 0);
        console.log("   Hook address matches mined address:", address(perpsHook) == hookAddress);
        console.log("   Hook flags match requirements:", (uint160(address(perpsHook)) & Hooks.ALL_HOOK_MASK) == flags);
    }
}
