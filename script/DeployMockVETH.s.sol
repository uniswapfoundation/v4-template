// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {MockVETH} from "../test/utils/mocks/MockVETH.sol";

/// @notice Deploys only MockVETH token
contract DeployMockVETHScript is Script {
    MockVETH public mockVETH;

    function run() public {
        vm.startBroadcast();

        // Deploy MockVETH
        mockVETH = new MockVETH();
        console.log("MockVETH deployed at:", address(mockVETH));
        console.log("MockVETH name:", mockVETH.name());
        console.log("MockVETH symbol:", mockVETH.symbol());
        console.log("MockVETH decimals:", mockVETH.decimals());

        // Mint initial supply to deployer (1K vETH)
        uint256 initialSupply = 1_000 * 10**mockVETH.decimals();
        mockVETH.mint(msg.sender, initialSupply);

        console.log("Initial supply minted:", initialSupply);
        console.log("Minted to deployer:", msg.sender);

        vm.stopBroadcast();

        console.log("\n=== MockVETH DEPLOYMENT SUMMARY ===");
        console.log("Contract Address:", address(mockVETH));
        console.log("Owner:", msg.sender);
        console.log("Initial Supply:", initialSupply);
        console.log("===================================");
    }
}
