// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {VCOPCollateralized} from "../src/VcopCollateral/VCOPCollateralized.sol";
import {VCOPOracle} from "../src/VcopCollateral/VCOPOracle.sol";
import {VCOPPriceCalculator} from "../src/VcopCollateral/VCOPPriceCalculator.sol";
import {VCOPCollateralManager} from "../src/VcopCollateral/VCOPCollateralManager.sol";
import {DeployMockUSDC} from "./DeployMockUSDC.s.sol";

/**
 * @title DeployVCOPBase
 * @notice Script to deploy the base contracts of the VCOP system
 * @dev To run: forge script script/DeployVCOPBase.sol:DeployVCOPBase --via-ir --broadcast --fork-url https://sepolia.base.org
 */
contract DeployVCOPBase is Script {
    // Dummy API Key to avoid verification errors
    string constant DUMMY_API_KEY = "ABCDEFGHIJKLMNOPQRSTUVWXYZ123456";
    
    // Initial USD/COP rate (4200 COP = 1 USD)
    uint256 initialUsdToCopRate = 4200e6; // With 6 decimals

    function run() public returns (
        address usdcAddress,
        address vcopAddress,
        address oracleAddress,
        address collateralManagerAddress
    ) {
        // Set a dummy API key for Etherscan
        vm.setEnv("ETHERSCAN_API_KEY", DUMMY_API_KEY);
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        
        console.logString("Verifying network and balances...");
        console.logString("Deployer address:"); 
        console.logAddress(deployerAddress);
        
        // === STEP 1: Deploy Simulated USDC ===
        console.logString("=== STEP 1: Deploying Simulated USDC ===");
        
        // Deploy simulated USDC
        DeployMockUSDC usdcDeployer = new DeployMockUSDC();
        usdcAddress = usdcDeployer.run();
        
        console.logString("Simulated USDC address:"); 
        console.logAddress(usdcAddress);
        
        // Save for the next script
        vm.setEnv("USDC_ADDRESS", vm.toString(usdcAddress));
        
        // === STEP 2: Deploy Collateralized VCOP ===
        console.logString("=== STEP 2: Deploying Collateralized VCOP ===");
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy Collateralized VCOP
        VCOPCollateralized vcop = new VCOPCollateralized();
        vcopAddress = address(vcop);
        
        console.logString("Collateralized VCOP deployed at:"); 
        console.logAddress(vcopAddress);
        
        vm.stopBroadcast();
        
        // Save for the next script
        vm.setEnv("VCOP_ADDRESS", vm.toString(vcopAddress));
        
        // === STEP 3: Deploy Oracle and Price Calculator ===
        console.logString("=== STEP 3: Deploying Oracle and Price Calculator ===");
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy oracle with initial rate
        VCOPOracle oracle = new VCOPOracle(
            initialUsdToCopRate,
            poolManagerAddress,
            vcopAddress,
            usdcAddress,
            3000, // lpFee 0.3%
            60,   // tickSpacing
            address(0) // Hook will be configured later
        );
        oracleAddress = address(oracle);
        
        console.logString("Oracle deployed at:"); 
        console.logAddress(oracleAddress);
        
        vm.stopBroadcast();
        
        // Save for the next script
        vm.setEnv("ORACLE_ADDRESS", vm.toString(oracleAddress));
        
        // === STEP 4: Deploy VCOPCollateralManager ===
        console.logString("=== STEP 4: Deploying Collateral Manager ===");
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the collateral manager
        VCOPCollateralManager collateralManager = new VCOPCollateralManager(
            vcopAddress,
            oracleAddress
        );
        collateralManagerAddress = address(collateralManager);
        
        console.logString("Collateral Manager deployed at:");
        console.logAddress(collateralManagerAddress);
        
        vm.stopBroadcast();
        
        // Save for the next script
        vm.setEnv("COLLATERAL_MANAGER_ADDRESS", vm.toString(collateralManagerAddress));
        
        console.logString("=== Base deployment successfully completed ===");
        console.logString("To continue, run ConfigureVCOPSystem.sol");
        
        return (usdcAddress, vcopAddress, oracleAddress, collateralManagerAddress);
    }
} 