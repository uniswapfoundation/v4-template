// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {MockUSDC} from "../test/utils/mocks/MockUSDC.sol";

/// @notice Deploys only MockUSDC token
contract DeployMockUSDCScript is Script {
    MockUSDC public mockUSDC;

    function run() public {
        vm.startBroadcast();

        // Deploy MockUSDC
        mockUSDC = new MockUSDC();
        console.log("MockUSDC deployed at:", address(mockUSDC));
        console.log("MockUSDC name:", mockUSDC.name());
        console.log("MockUSDC symbol:", mockUSDC.symbol());
        console.log("MockUSDC decimals:", mockUSDC.decimals());

        // Mint initial supply to deployer (1M USDC)
        uint256 initialSupply = 1_000_000 * 10**mockUSDC.decimals();
        mockUSDC.mint(msg.sender, initialSupply);

        console.log("Initial supply minted:", initialSupply);
        console.log("Minted to deployer:", msg.sender);

        vm.stopBroadcast();

        console.log("\n=== MockUSDC DEPLOYMENT SUMMARY ===");
        console.log("Contract Address:", address(mockUSDC));
        console.log("Owner:", msg.sender);
        console.log("Initial Supply:", initialSupply);
        console.log("===================================");
    }
}
