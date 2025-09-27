// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {InsuranceFund} from "../src/InsuranceFund.sol";

contract DeployInsuranceFundScript is Script {
    // Known addresses from previous deployments
    address constant USDC_ADDRESS = 0x5FbDB2315678afecb367f032d93F642f64180aa3; // MockUSDC
    
    function run() external {
        console.log("Deploying InsuranceFund with USDC:", USDC_ADDRESS);
        console.log("Deployer address:", msg.sender);
        console.log("Deployer balance:", msg.sender.balance);
        
        vm.startBroadcast();
        
        // Deploy InsuranceFund
        InsuranceFund insuranceFund = new InsuranceFund(USDC_ADDRESS);
        
        console.log("InsuranceFund deployed to:", address(insuranceFund));
        console.log("USDC token set to:", address(insuranceFund.USDC()));
        console.log("Owner set to:", insuranceFund.owner());
        console.log("Min fund balance:", insuranceFund.minFundBalance() / 1e6, "USDC");
        console.log("Max coverage per event:", insuranceFund.maxCoveragePerEvent() / 1e6, "USDC");
        
        vm.stopBroadcast();
    }
}
