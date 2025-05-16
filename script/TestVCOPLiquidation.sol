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
 * @title TestVCOPLiquidation
 * @notice Script to test the VCOP loan liquidation mechanism with the deployed contracts
 * Tests the following scenario:
 * 1. Create a high-risk position with minimal collateral (close to the liquidation threshold)
 * 2. Check if the position is liquidatable (it shouldn't be initially)
 * 3. Try to liquidate the position (should fail)
 */
contract TestVCOPLiquidation is Script {
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
    uint256 collateralAmount = 500 * 1e6; // 500 USDC as collateral
    
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
        
        // 1. Check USDC and VCOP balances
        console.log("=== Initial balances ===");
        uint256 initialUsdcBalance = usdc.balanceOf(deployerAddress);
        uint256 initialVcopBalance = vcop.balanceOf(deployerAddress);
        console.log("USDC balance:", initialUsdcBalance / 1e6);
        console.log("VCOP balance:", initialVcopBalance / 1e6);
        
        // 2. Approve USDC for creating a position
        usdc.approve(COLLATERAL_MANAGER_ADDRESS, collateralAmount);
        console.log("Approved USDC for collateral manager");
        
        // 3. Get information about the collateral asset
        (
            address tokenAddress,
            uint256 ratio,
            uint256 mintFee,
            uint256 burnFee,
            uint256 liquidationThreshold,
            bool active
        ) = collateralManager.collaterals(USDC_ADDRESS);
        
        console.log("Collateral configuration:");
        console.log("- Collateralization ratio:", ratio / 10000, "%");
        console.log("- Liquidation threshold:", liquidationThreshold / 10000, "%");
        
        // 4. Get maximum VCOP that can be minted with our collateral
        uint256 maxVcop = collateralManager.getMaxVCOPforCollateral(USDC_ADDRESS, collateralAmount);
        console.log("Maximum VCOP for", collateralAmount / 1e6, "USDC collateral:", maxVcop / 1e6);
        
        // 5. Use 95% of the maximum VCOP to mint (to create a high-risk position close to liquidation)
        uint256 vcopToMint = (maxVcop * 95) / 100;
        console.log("VCOP to mint (95% of max):", vcopToMint / 1e6);
        
        // Calculate expected collateralization ratio
        uint256 collateralValue = collateralManager.getCollateralValue(USDC_ADDRESS, collateralAmount);
        uint256 expectedRatio = (collateralValue * 1000000) / vcopToMint;
        console.log("Expected collateralization ratio:", expectedRatio / 10000, "%");
        
        // Verify this is above the liquidation threshold but close to it
        console.log("Position will be safe? ", expectedRatio > liquidationThreshold ? "Yes" : "No");
        console.log("Position is close to liquidation? ", 
                   (expectedRatio < liquidationThreshold + 100000) ? "Yes" : "No");
        
        // 6. Create a position with high risk (close to liquidation threshold)
        console.log("\n=== Creating high-risk loan position ===");
        
        // Get initial position count
        uint256 initialPositionCount = collateralManager.positionCount(deployerAddress);
        console.log("Initial position count:", initialPositionCount);
        
        // Create position
        collateralManager.createPosition(USDC_ADDRESS, collateralAmount, vcopToMint);
        
        // Get updated position count
        uint256 updatedPositionCount = collateralManager.positionCount(deployerAddress);
        console.log("Updated position count:", updatedPositionCount);
        
        // Get position ID (should be the initial count)
        uint256 positionId = initialPositionCount;
        
        // Get position details
        (address collateralToken, uint256 positionCollateral, uint256 positionVcopMinted) = 
            collateralManager.positions(deployerAddress, positionId);
        
        console.log("Position created:");
        console.log("- Position ID:", positionId);
        console.log("- Collateral amount:", positionCollateral / 1e6, "USDC");
        console.log("- VCOP minted:", positionVcopMinted / 1e6, "VCOP");
        
        // Calculate and display the current collateralization ratio
        uint256 collateralRatio = collateralManager.getCurrentCollateralRatio(deployerAddress, positionId);
        console.log("Current collateralization ratio:", collateralRatio / 10000, "%");
        
        // 7. Check if the position is liquidatable
        console.log("\n=== Checking if position is liquidatable ===");
        bool isLiquidatable = collateralRatio < liquidationThreshold;
        console.log("Position is liquidatable:", isLiquidatable);
        
        // 8. Try to liquidate the position (will revert if not liquidatable)
        if (isLiquidatable) {
            console.log("Attempting to liquidate position...");
            
            // Approve VCOP for burning during liquidation
            vcop.approve(COLLATERAL_MANAGER_ADDRESS, positionVcopMinted);
            
            try collateralManager.liquidatePosition(deployerAddress, positionId) {
                console.log("Position successfully liquidated!");
                
                // Check position status after liquidation
                (collateralToken, positionCollateral, positionVcopMinted) = 
                    collateralManager.positions(deployerAddress, positionId);
                
                console.log("Position after liquidation:");
                console.log("- Collateral amount:", positionCollateral / 1e6, "USDC");
                console.log("- VCOP debt remaining:", positionVcopMinted / 1e6, "VCOP");
                
                if (positionCollateral == 0 && positionVcopMinted == 0) {
                    console.log("Position was closed by liquidation!");
                }
            } catch Error(string memory reason) {
                console.log("Liquidation failed with reason:", reason);
            } catch {
                console.log("Liquidation failed with unknown error");
            }
        } else {
            console.log("Position is not liquidatable - skipping liquidation attempt");
        }
        
        // 9. Check final balances
        console.log("\n=== Final balances ===");
        uint256 finalUsdcBalance = usdc.balanceOf(deployerAddress);
        uint256 finalVcopBalance = vcop.balanceOf(deployerAddress);
        console.log("USDC balance:", finalUsdcBalance / 1e6);
        console.log("VCOP balance:", finalVcopBalance / 1e6);
        console.log("USDC change:", (finalUsdcBalance - initialUsdcBalance) / 1e6);
        console.log("VCOP change:", (finalVcopBalance - initialVcopBalance) / 1e6);
        
        vm.stopBroadcast();
    }
} 