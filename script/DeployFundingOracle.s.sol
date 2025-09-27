// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {FundingOracle} from "../src/FundingOracle.sol";

contract DeployFundingOracleScript is Script {
    
    function run() external {
        console.log("Deploying FundingOracle");
        console.log("Deployer address:", msg.sender);
        console.log("Deployer balance:", msg.sender.balance);
        
        vm.startBroadcast();
        
        // Deploy FundingOracle
        address pythContract = address(0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF); // Placeholder for Pyth
        FundingOracle fundingOracle = new FundingOracle(pythContract);
        
        console.log("FundingOracle deployed to:", address(fundingOracle));
        console.log("Owner set to:", fundingOracle.owner());
        console.log("Default funding interval:", fundingOracle.DEFAULT_FUNDING_INTERVAL() / 3600, "hours");
        console.log("Default max funding rate:", uint256(fundingOracle.DEFAULT_MAX_FUNDING_RATE()) / 1e16, "% per interval");
        
        vm.stopBroadcast();
    }
}
