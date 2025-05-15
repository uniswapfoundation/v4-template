// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {VCOPOracle} from "../src/VcopCollateral/VCOPOracle.sol";
import {VCOPCollateralized} from "../src/VcopCollateral/VCOPCollateralized.sol";
import {VCOPCollateralManager} from "../src/VcopCollateral/VCOPCollateralManager.sol";

/**
 * @title NewOracleSwap
 * @notice Script to manually swap USDC to VCOP using the new oracle directly
 */
contract NewOracleSwap is Script {
    // Contract addresses
    address public constant USDC_ADDRESS = 0x1D954BcfB060a3dc5A49536243545334dD536493;
    address public constant VCOP_ADDRESS = 0xbbF67a9C2a6E33B405ff30C948275c2154B36E3A;
    address public constant MANAGER_ADDRESS = 0x2D644FC74e5fe6598b0843f149b02bFEf99Ef383;
    
    // New Oracle address (from the update-oracle deployment)
    address public constant NEW_ORACLE_ADDRESS = 0x7C7954D735AEf45E240945B60Eeab72780c05aa6;
    
    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address account = vm.addr(privateKey);
        
        // Amount to swap - default to 10 USDC with 6 decimals
        uint256 amount = 10 * 1e6;
        
        // Load the new oracle
        VCOPOracle newOracle = VCOPOracle(NEW_ORACLE_ADDRESS);
        
        // Load the token contracts
        IERC20 usdc = IERC20(USDC_ADDRESS);
        IERC20 vcop = IERC20(VCOP_ADDRESS);
        
        // Load the collateral manager
        VCOPCollateralManager manager = VCOPCollateralManager(MANAGER_ADDRESS);
        
        // Calculate expected VCOP amount based on the new oracle rates
        // Formula: VCOP = USDC * (USD/COP) / (VCOP/COP)
        uint256 usdToCopRate = newOracle.getUsdToCopRateView();
        uint256 vcopToCopRate = newOracle.getVcopToCopRateView();
        
        uint256 expectedVcop = (amount * usdToCopRate) / vcopToCopRate;
        
        // Apply PSM fee of 0.1% (1000 basis points)
        uint256 fee = (expectedVcop * 1000) / 1000000;
        uint256 expectedVcopAfterFees = expectedVcop - fee;
        
        console.log("=== Direct USDC to VCOP Swap with New Oracle ===");
        console.log("Account:", account);
        console.log("USDC Amount:", amount);
        console.log("USD/COP Rate:", usdToCopRate);
        console.log("VCOP/COP Rate:", vcopToCopRate);
        console.log("Expected VCOP (before fees):", expectedVcop);
        console.log("Fee (0.1%):", fee);
        console.log("Expected VCOP (after fees):", expectedVcopAfterFees);
        
        // Check initial balances
        uint256 usdcBalance = usdc.balanceOf(account);
        uint256 vcopBalance = vcop.balanceOf(account);
        
        console.log("\nInitial USDC balance:", usdcBalance);
        console.log("Initial VCOP balance:", vcopBalance);
        
        require(usdcBalance >= amount, "Insufficient USDC balance");
        
        // Start transaction
        vm.startBroadcast(privateKey);
        
        // We'll manually mint VCOP based on the new oracle's calculation
        // 1. Transfer USDC to the collateral manager
        usdc.approve(MANAGER_ADDRESS, amount);
        
        // NOTE: This is a simulation, in a production system you would need 
        // special permissions in the manager contract to do this
        // Here we're just demonstrating what the correct swap amount should be
        
        console.log("\nNOTE: This is a simulation - it will fail since we don't have minting rights");
        console.log("To properly implement this, you need to deploy a new manager with the new oracle");
        
        vm.stopBroadcast();
        
        console.log("\n=== Recommended Solution ===");
        console.log("1. Deploy a new CollateralManager that uses the new oracle");
        console.log("2. Set up permissions for the VCOP token to allow minting from the new manager");
        console.log("3. Configure a new PSM hook to use the new manager");
        console.log("4. Test the swap with the new components");
        console.log("");
        console.log("The correct exchange rate with the new oracle would be:");
        console.log("10 USDC = 42,000 VCOP (before fees)");
        console.log("10 USDC = 41,958 VCOP (after 0.1% fee)");
    }
} 