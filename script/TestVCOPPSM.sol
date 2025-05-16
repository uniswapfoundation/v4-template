// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {IERC20} from "v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {VCOPCollateralManager} from "../src/VcopCollateral/VCOPCollateralManager.sol";
import {VCOPCollateralized} from "../src/VcopCollateral/VCOPCollateralized.sol";
import {VCOPOracle} from "../src/VcopCollateral/VCOPOracle.sol";
import {VCOPCollateralHook} from "../src/VcopCollateral/VCOPCollateralHook.sol";

/**
 * @title TestVCOPPSM
 * @notice Script to test the VCOP PSM (Peg Stability Module) with the deployed contracts
 * Tests the following functions:
 * 1. Check PSM status and reserves
 * 2. Test PSM swap from VCOP to USDC
 * 3. Test PSM swap from USDC to VCOP
 */
contract TestVCOPPSM is Script {
    // Deployed contract addresses
    address constant USDC_ADDRESS = 0x55D917171766710BB0B94ed56aAb39EfA1692a34;
    address constant VCOP_ADDRESS = 0x273860ddf28A478136B935E458b272876AB22Ab5;
    address constant ORACLE_ADDRESS = 0x366F0428E3A548AA36bA4c0F7C1A8829d9d68518;
    address constant COLLATERAL_MANAGER_ADDRESS = 0x66b2f53A83ae8f1ff790c6C16F252B22D94e1f39;
    address constant HOOK_ADDRESS = 0x9840E0F348aC72088ADB702F7CFfB1B7403184C0;
    address constant PRICE_CALCULATOR_ADDRESS = 0x0Df3Ee10A5eEd46DDc5B3ea8d471ea657EF5a544;
    
    // Contract instances
    IERC20 usdc;
    VCOPCollateralized vcop;
    VCOPCollateralManager collateralManager;
    VCOPOracle oracle;
    VCOPCollateralHook hook;
    
    // Test parameters
    uint256 swapAmount = 100 * 1e6; // 100 tokens with 6 decimals
    
    function run() external {
        // Get the private key from environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        console.log("Script runner address:", deployerAddress);
        
        // Initialize contract instances
        usdc = IERC20(USDC_ADDRESS);
        vcop = VCOPCollateralized(VCOP_ADDRESS);
        collateralManager = VCOPCollateralManager(COLLATERAL_MANAGER_ADDRESS);
        oracle = VCOPOracle(ORACLE_ADDRESS);
        hook = VCOPCollateralHook(HOOK_ADDRESS);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Check PSM status
        checkPSMStatus();
        
        // 2. Test VCOP to USDC swap
        swapVCOPToUSDC();
        
        // 3. Test USDC to VCOP swap
        swapUSDCToVCOP();
        
        vm.stopBroadcast();
    }
    
    function checkPSMStatus() public {
        console.log("\n=== Checking PSM Status ===");
        
        // Get PSM statistics
        (
            uint256 vcopReserve,
            uint256 collateralReserve,
            uint256 lastOperationTimestamp,
            uint256 totalSwapsCount
        ) = hook.getPSMStats();
        
        console.log("PSM Reserves:");
        console.log("- VCOP reserve:", vcopReserve / 1e6);
        console.log("- USDC collateral reserve:", collateralReserve / 1e6);
        console.log("Last operation timestamp:", lastOperationTimestamp);
        console.log("Total PSM swaps count:", totalSwapsCount);
        
        // Get PSM parameters
        uint256 pegUpperBound = hook.pegUpperBound();
        uint256 pegLowerBound = hook.pegLowerBound();
        uint256 psmFee = hook.psmFee();
        uint256 psmMaxSwapAmount = hook.psmMaxSwapAmount();
        bool psmPaused = hook.psmPaused();
        
        console.log("\nPSM Parameters:");
        console.log("- Peg upper bound:", pegUpperBound / 10000, "%");
        console.log("- Peg lower bound:", pegLowerBound / 10000, "%");
        console.log("- PSM fee:", psmFee / 10000, "%");
        console.log("- PSM max swap amount:", psmMaxSwapAmount / 1e6, "VCOP");
        console.log("- PSM paused:", psmPaused);
        
        // Check if the PSM has sufficient reserves
        bool hasReserves = collateralManager.hasPSMReservesFor(USDC_ADDRESS, swapAmount);
        console.log("Has sufficient PSM reserves for", swapAmount / 1e6, "USDC:", hasReserves);
        
        // Get PSM reserves directly from collateral manager
        (uint256 collateralAmount, uint256 vcopAmount, bool active) = 
            collateralManager.getPSMReserves(USDC_ADDRESS);
            
        console.log("\nPSM Reserves from Collateral Manager:");
        console.log("- Collateral amount:", collateralAmount / 1e6, "USDC");
        console.log("- VCOP amount:", vcopAmount / 1e6, "VCOP");
        console.log("- Active:", active);
    }
    
    function swapVCOPToUSDC() public {
        console.log("\n=== Testing VCOP to USDC Swap ===");
        
        // Check initial balances
        uint256 initialUsdcBalance = usdc.balanceOf(address(this));
        uint256 initialVcopBalance = vcop.balanceOf(address(this));
        console.log("Initial USDC balance:", initialUsdcBalance / 1e6);
        console.log("Initial VCOP balance:", initialVcopBalance / 1e6);
        
        // Calculate expected output amount
        uint256 collateralForVcop = hook.calculateCollateralForVCOPView(swapAmount);
        uint256 fee = (collateralForVcop * hook.psmFee()) / 1000000;
        uint256 expectedOutput = collateralForVcop - fee;
        
        console.log("Swapping", swapAmount / 1e6, "VCOP for USDC");
        console.log("Expected output (before fee):", collateralForVcop / 1e6, "USDC");
        console.log("Fee:", fee / 1e6, "USDC");
        console.log("Expected output (after fee):", expectedOutput / 1e6, "USDC");
        
        // Check VCOP balance and approve for swap
        uint256 vcopBalance = vcop.balanceOf(address(this));
        if (vcopBalance < swapAmount) {
            console.log("Insufficient VCOP balance for swap. Skipping...");
            return;
        }
        
        // Approve VCOP for the hook
        vcop.approve(HOOK_ADDRESS, swapAmount);
        
        // Execute swap
        try hook.psmSwapVCOPForCollateral(swapAmount) {
            console.log("Swap executed successfully");
            
            // Check final balances
            uint256 finalUsdcBalance = usdc.balanceOf(address(this));
            uint256 finalVcopBalance = vcop.balanceOf(address(this));
            console.log("Final USDC balance:", finalUsdcBalance / 1e6);
            console.log("Final VCOP balance:", finalVcopBalance / 1e6);
            console.log("USDC gained:", (finalUsdcBalance - initialUsdcBalance) / 1e6);
            console.log("VCOP spent:", (initialVcopBalance - finalVcopBalance) / 1e6);
        } catch Error(string memory reason) {
            console.log("Swap failed with reason:", reason);
        } catch {
            console.log("Swap failed with unknown error");
        }
    }
    
    function swapUSDCToVCOP() public {
        console.log("\n=== Testing USDC to VCOP Swap ===");
        
        // Check initial balances
        uint256 initialUsdcBalance = usdc.balanceOf(address(this));
        uint256 initialVcopBalance = vcop.balanceOf(address(this));
        console.log("Initial USDC balance:", initialUsdcBalance / 1e6);
        console.log("Initial VCOP balance:", initialVcopBalance / 1e6);
        
        // Calculate expected output amount
        uint256 vcopForCollateral = hook.calculateVCOPForCollateralView(swapAmount);
        uint256 fee = (vcopForCollateral * hook.psmFee()) / 1000000;
        uint256 expectedOutput = vcopForCollateral - fee;
        
        console.log("Swapping", swapAmount / 1e6, "USDC for VCOP");
        console.log("Expected output (before fee):", vcopForCollateral / 1e6, "VCOP");
        console.log("Fee:", fee / 1e6, "VCOP");
        console.log("Expected output (after fee):", expectedOutput / 1e6, "VCOP");
        
        // Check USDC balance and approve for swap
        uint256 usdcBalance = usdc.balanceOf(address(this));
        if (usdcBalance < swapAmount) {
            console.log("Insufficient USDC balance for swap. Skipping...");
            return;
        }
        
        // Approve USDC for the hook
        usdc.approve(HOOK_ADDRESS, swapAmount);
        
        // Execute swap
        try hook.psmSwapCollateralForVCOP(swapAmount) {
            console.log("Swap executed successfully");
            
            // Check final balances
            uint256 finalUsdcBalance = usdc.balanceOf(address(this));
            uint256 finalVcopBalance = vcop.balanceOf(address(this));
            console.log("Final USDC balance:", finalUsdcBalance / 1e6);
            console.log("Final VCOP balance:", finalVcopBalance / 1e6);
            console.log("USDC spent:", (initialUsdcBalance - finalUsdcBalance) / 1e6);
            console.log("VCOP gained:", (finalVcopBalance - initialVcopBalance) / 1e6);
        } catch Error(string memory reason) {
            console.log("Swap failed with reason:", reason);
        } catch {
            console.log("Swap failed with unknown error");
        }
    }
    
    // Individual function for checking PSM status (can be called directly with --sig)
    function checkPSM() external {
        // Get the private key from environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Initialize contract instances
        usdc = IERC20(USDC_ADDRESS);
        vcop = VCOPCollateralized(VCOP_ADDRESS);
        collateralManager = VCOPCollateralManager(COLLATERAL_MANAGER_ADDRESS);
        oracle = VCOPOracle(ORACLE_ADDRESS);
        hook = VCOPCollateralHook(HOOK_ADDRESS);
        
        // Check status
        checkPSMStatus();
        
        vm.stopBroadcast();
    }
    
    // Individual function for VCOP to USDC swap (can be called directly with --sig)
    function swapVcopToUsdc(uint256 amount) external {
        // Get the private key from environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Initialize contract instances
        usdc = IERC20(USDC_ADDRESS);
        vcop = VCOPCollateralized(VCOP_ADDRESS);
        collateralManager = VCOPCollateralManager(COLLATERAL_MANAGER_ADDRESS);
        oracle = VCOPOracle(ORACLE_ADDRESS);
        hook = VCOPCollateralHook(HOOK_ADDRESS);
        
        // Check balances
        uint256 initialUsdcBalance = usdc.balanceOf(deployerAddress);
        uint256 initialVcopBalance = vcop.balanceOf(deployerAddress);
        console.log("Initial USDC balance:", initialUsdcBalance / 1e6);
        console.log("Initial VCOP balance:", initialVcopBalance / 1e6);
        
        // Approve VCOP for the hook
        vcop.approve(HOOK_ADDRESS, amount);
        
        // Execute swap
        try hook.psmSwapVCOPForCollateral(amount) {
            console.log("Swap executed successfully");
            
            // Check final balances
            uint256 finalUsdcBalance = usdc.balanceOf(deployerAddress);
            uint256 finalVcopBalance = vcop.balanceOf(deployerAddress);
            console.log("Final USDC balance:", finalUsdcBalance / 1e6);
            console.log("Final VCOP balance:", finalVcopBalance / 1e6);
            console.log("USDC gained:", (finalUsdcBalance - initialUsdcBalance) / 1e6);
            console.log("VCOP spent:", (initialVcopBalance - finalVcopBalance) / 1e6);
        } catch Error(string memory reason) {
            console.log("Swap failed with reason:", reason);
        } catch {
            console.log("Swap failed with unknown error");
        }
        
        vm.stopBroadcast();
    }
    
    // Individual function for USDC to VCOP swap (can be called directly with --sig)
    function swapUsdcToVcop(uint256 amount) external {
        // Get the private key from environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Initialize contract instances
        usdc = IERC20(USDC_ADDRESS);
        vcop = VCOPCollateralized(VCOP_ADDRESS);
        collateralManager = VCOPCollateralManager(COLLATERAL_MANAGER_ADDRESS);
        oracle = VCOPOracle(ORACLE_ADDRESS);
        hook = VCOPCollateralHook(HOOK_ADDRESS);
        
        // Check balances
        uint256 initialUsdcBalance = usdc.balanceOf(deployerAddress);
        uint256 initialVcopBalance = vcop.balanceOf(deployerAddress);
        console.log("Initial USDC balance:", initialUsdcBalance / 1e6);
        console.log("Initial VCOP balance:", initialVcopBalance / 1e6);
        
        // Approve USDC for the hook
        usdc.approve(HOOK_ADDRESS, amount);
        
        // Execute swap
        try hook.psmSwapCollateralForVCOP(amount) {
            console.log("Swap executed successfully");
            
            // Check final balances
            uint256 finalUsdcBalance = usdc.balanceOf(deployerAddress);
            uint256 finalVcopBalance = vcop.balanceOf(deployerAddress);
            console.log("Final USDC balance:", finalUsdcBalance / 1e6);
            console.log("Final VCOP balance:", finalVcopBalance / 1e6);
            console.log("USDC spent:", (initialUsdcBalance - finalUsdcBalance) / 1e6);
            console.log("VCOP gained:", (finalVcopBalance - initialVcopBalance) / 1e6);
        } catch Error(string memory reason) {
            console.log("Swap failed with reason:", reason);
        } catch {
            console.log("Swap failed with unknown error");
        }
        
        vm.stopBroadcast();
    }
} 