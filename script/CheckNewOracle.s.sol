// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {VCOPOracle} from "../src/VcopCollateral/VCOPOracle.sol";

/**
 * @title CheckNewOracle
 * @notice Script to check rates from the new oracle
 */
contract CheckNewOracle is Script {
    // Old Oracle address
    address public constant OLD_ORACLE_ADDRESS = 0x352a80294311db57562f625cFcab502ccAd61581;
    
    // New Oracle address (from the update-oracle deployment)
    address public constant NEW_ORACLE_ADDRESS = 0x7C7954D735AEf45E240945B60Eeab72780c05aa6;
    
    function run() public {
        // No private key needed for view calls
        
        // Load the old oracle for comparison
        VCOPOracle oldOracle = VCOPOracle(OLD_ORACLE_ADDRESS);
        
        // Load the new oracle
        VCOPOracle newOracle = VCOPOracle(NEW_ORACLE_ADDRESS);
        
        console.log("=== Oracle Comparison ===");
        
        // Check old oracle rates
        console.log("--- Old Oracle ---");
        console.log("Address:", OLD_ORACLE_ADDRESS);
        console.log("VCOP/COP rate:", oldOracle.getVcopToCopRateView());
        console.log("USD/COP rate:", oldOracle.getUsdToCopRateView());
        
        // Check new oracle rates
        console.log("--- New Oracle ---");
        console.log("Address:", NEW_ORACLE_ADDRESS);
        console.log("VCOP/COP rate:", newOracle.getVcopToCopRateView());
        console.log("USD/COP rate:", newOracle.getUsdToCopRateView());
        
        // Calculate example swaps with both oracles
        uint256 testAmount = 100 * 1e6; // 100 tokens with 6 decimals
        
        console.log("\n=== VCOP/USD Calculation Examples ===");
        console.log("For 100 VCOP:");
        
        // Calculate with old oracle values
        uint256 oldOracleVcopVal = (testAmount * oldOracle.getVcopToCopRateView()) / 1e6;
        uint256 oldOracleUsdVal = oldOracleVcopVal / (oldOracle.getUsdToCopRateView() / 1e6);
        console.log("Old Oracle: 100 VCOP = %s USD", oldOracleUsdVal);
        
        // Calculate with new oracle values  
        uint256 newOracleVcopVal = (testAmount * newOracle.getVcopToCopRateView()) / 1e6;
        uint256 newOracleUsdVal = newOracleVcopVal / (newOracle.getUsdToCopRateView() / 1e6);
        console.log("New Oracle: 100 VCOP = %s USD", newOracleUsdVal);
        
        console.log("\nFor 100 USD:");
        // Old oracle: USD to VCOP
        uint256 oldOracleVcop = (testAmount * (oldOracle.getUsdToCopRateView() / 1e6)) / (oldOracle.getVcopToCopRateView() / 1e6);
        console.log("Old Oracle: 100 USD = %s VCOP", oldOracleVcop);
        
        // New oracle: USD to VCOP  
        uint256 newOracleVcop = (testAmount * (newOracle.getUsdToCopRateView() / 1e6)) / (newOracle.getVcopToCopRateView() / 1e6);
        console.log("New Oracle: 100 USD = %s VCOP", newOracleVcop);
    }
} 