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
 * @title TestVCOPLoans
 * @notice Script to test the VCOP loan system with the deployed contracts
 * Tests the following functions:
 * 1. Create a loan position with USDC collateral
 * 2. Add more collateral to existing position
 * 3. Withdraw some collateral
 * 4. Repay part of the loan
 * 5. Repay the rest of the loan to close the position
 */
contract TestVCOPLoans is Script {
    // Deployed contract addresses
    address constant USDC_ADDRESS = 0x5405e3a584014c8659BA10591c1b7D55cB1cFc0d;
    address constant VCOP_ADDRESS = 0x3D384BeB1Ba0197e6a87668E1D68267164c8B776;
    address constant ORACLE_ADDRESS = 0x046fFDe3161CD0a8DCBF7e1c433f5f510703d56d;
    address constant COLLATERAL_MANAGER_ADDRESS = 0x8f17E2128a4F917ec4147c15FC90bADd79E7F090;
    address constant HOOK_ADDRESS = 0xb1D909689f88Bd34340f477A0Bad3956113944C0;
    address constant PRICE_CALCULATOR_ADDRESS = 0x12C8498b96714615B7bF98456058D48e01C59DB3;
    
    // Contract instances
    IERC20 usdc;
    VCOPCollateralized vcop;
    VCOPCollateralManager collateralManager;
    VCOPOracle oracle;
    VCOPCollateralHook hook;
    
    // Test parameters
    uint256 collateralAmount = 1000 * 1e6; // 1,000 USDC as collateral
    uint256 addCollateralAmount = 500 * 1e6; // 500 USDC to add later
    
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
        
        // 1. Check initial balances
        console.log("=== Initial balances ===");
        uint256 initialUsdcBalance = usdc.balanceOf(deployerAddress);
        uint256 initialVcopBalance = vcop.balanceOf(deployerAddress);
        console.log("USDC balance:", initialUsdcBalance / 1e6);
        console.log("VCOP balance:", initialVcopBalance / 1e6);
        
        // Check USDC allowance for collateral manager
        uint256 usdcAllowance = usdc.allowance(deployerAddress, COLLATERAL_MANAGER_ADDRESS);
        console.log("Current USDC allowance for collateral manager:", usdcAllowance / 1e6);
        
        // Approve USDC for collateral manager if needed
        if (usdcAllowance < collateralAmount + addCollateralAmount) {
            usdc.approve(COLLATERAL_MANAGER_ADDRESS, type(uint256).max);
            console.log("Approved USDC for collateral manager");
        }
        
        // 2. Get maximum VCOP that can be minted with our collateral
        uint256 maxVcop = collateralManager.getMaxVCOPforCollateral(USDC_ADDRESS, collateralAmount);
        console.log("Maximum VCOP for", collateralAmount / 1e6, "USDC collateral:", maxVcop / 1e6);
        
        // Use 80% of the maximum VCOP to mint (to maintain a safer collateralization ratio)
        uint256 vcopToMint = (maxVcop * 80) / 100;
        console.log("VCOP to mint (80% of max):", vcopToMint / 1e6);
        
        // 3. Create a position
        console.log("\n=== Creating loan position ===");
        
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
        console.log("- Collateral token:", collateralToken);
        console.log("- Collateral amount:", positionCollateral / 1e6, "USDC");
        console.log("- VCOP minted:", positionVcopMinted / 1e6, "VCOP");
        
        // Calculate and display the current collateralization ratio
        uint256 collateralRatio = collateralManager.getCurrentCollateralRatio(deployerAddress, positionId);
        console.log("Current collateralization ratio:", collateralRatio / 10000, "%");
        
        // 4. Add more collateral to the position
        console.log("\n=== Adding more collateral ===");
        collateralManager.addCollateral(positionId, addCollateralAmount);
        
        // Get updated position details
        (collateralToken, positionCollateral, positionVcopMinted) = 
            collateralManager.positions(deployerAddress, positionId);
        
        console.log("Position after adding collateral:");
        console.log("- Collateral amount:", positionCollateral / 1e6, "USDC");
        console.log("- VCOP minted:", positionVcopMinted / 1e6, "VCOP");
        
        // Calculate and display the new collateralization ratio
        collateralRatio = collateralManager.getCurrentCollateralRatio(deployerAddress, positionId);
        console.log("New collateralization ratio:", collateralRatio / 10000, "%");
        
        // 5. Withdraw some collateral (25% of the additional amount)
        console.log("\n=== Withdrawing some collateral ===");
        uint256 withdrawAmount = addCollateralAmount / 4;
        collateralManager.withdrawCollateral(positionId, withdrawAmount);
        
        // Get updated position details
        (collateralToken, positionCollateral, positionVcopMinted) = 
            collateralManager.positions(deployerAddress, positionId);
        
        console.log("Position after withdrawing collateral:");
        console.log("- Collateral amount:", positionCollateral / 1e6, "USDC");
        console.log("- VCOP minted:", positionVcopMinted / 1e6, "VCOP");
        
        // Calculate and display the new collateralization ratio
        collateralRatio = collateralManager.getCurrentCollateralRatio(deployerAddress, positionId);
        console.log("New collateralization ratio:", collateralRatio / 10000, "%");
        
        // 6. Repay part of the debt (30% of the minted VCOP)
        console.log("\n=== Repaying part of the debt ===");
        uint256 repayAmount = (vcopToMint * 30) / 100;
        
        // Check VCOP balance and approve for repayment
        uint256 vcopBalance = vcop.balanceOf(deployerAddress);
        console.log("Current VCOP balance:", vcopBalance / 1e6);
        console.log("VCOP to repay:", repayAmount / 1e6);
        
        // Approve VCOP for burning
        vcop.approve(COLLATERAL_MANAGER_ADDRESS, repayAmount);
        
        // Repay debt
        collateralManager.repayDebt(positionId, repayAmount);
        
        // Get updated position details
        (collateralToken, positionCollateral, positionVcopMinted) = 
            collateralManager.positions(deployerAddress, positionId);
        
        console.log("Position after partial repayment:");
        console.log("- Collateral amount:", positionCollateral / 1e6, "USDC");
        console.log("- VCOP debt remaining:", positionVcopMinted / 1e6, "VCOP");
        
        // Calculate and display the new collateralization ratio
        collateralRatio = collateralManager.getCurrentCollateralRatio(deployerAddress, positionId);
        console.log("New collateralization ratio:", collateralRatio / 10000, "%");
        
        // 7. Repay the rest of the debt to close the position
        console.log("\n=== Repaying remaining debt to close position ===");
        
        // Approve VCOP for full repayment
        vcop.approve(COLLATERAL_MANAGER_ADDRESS, positionVcopMinted);
        
        // Repay all remaining debt
        collateralManager.repayDebt(positionId, positionVcopMinted);
        
        // Get updated position details
        (collateralToken, positionCollateral, positionVcopMinted) = 
            collateralManager.positions(deployerAddress, positionId);
        
        console.log("Position after full repayment:");
        console.log("- Collateral amount:", positionCollateral / 1e6, "USDC");
        console.log("- VCOP debt remaining:", positionVcopMinted / 1e6, "VCOP");
        
        if (positionCollateral == 0 && positionVcopMinted == 0) {
            console.log("Position successfully closed!");
        } else {
            console.log("Position still has assets or debt!");
        }
        
        // 8. Check final balances
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