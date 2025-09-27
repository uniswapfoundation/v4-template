// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {MarginAccount} from "../src/MarginAccount.sol";

contract DeployMarginAccountScript is Script {
    // Known addresses from previous deployments
    address constant USDC_ADDRESS = 0x5FbDB2315678afecb367f032d93F642f64180aa3; // MockUSDC
    
    function run() external {
        console.log("Deploying MarginAccount with USDC:", USDC_ADDRESS);
        console.log("Deployer address:", msg.sender);
        console.log("Deployer balance:", msg.sender.balance);
        
        vm.startBroadcast();
        
        // Deploy MarginAccount
        MarginAccount marginAccount = new MarginAccount(USDC_ADDRESS);
        
        console.log("MarginAccount deployed to:", address(marginAccount));
        console.log("USDC token set to:", address(marginAccount.USDC()));
        console.log("Owner set to:", marginAccount.owner());
        
        vm.stopBroadcast();
    }
}
