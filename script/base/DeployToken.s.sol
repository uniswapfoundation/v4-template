// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {MockUSDC} from "../../test/utils/mocks/MockUSDC.sol";
import {MockVETH} from "../../test/utils/mocks/MockVETH.sol";

/// @notice Deploys MockUSDC and MockVETH tokens
contract DeployTokenScript is Script {
    MockUSDC public mockUSDC;
    MockVETH public mockVETH;

    function run() public {
        vm.startBroadcast();

        // Deploy MockUSDC
        mockUSDC = new MockUSDC();
        console.log("MockUSDC deployed at:", address(mockUSDC));
        console.log("MockUSDC name:", mockUSDC.name());
        console.log("MockUSDC symbol:", mockUSDC.symbol());
        console.log("MockUSDC decimals:", mockUSDC.decimals());

        // Deploy MockVETH
        mockVETH = new MockVETH();
        console.log("MockVETH deployed at:", address(mockVETH));
        console.log("MockVETH name:", mockVETH.name());
        console.log("MockVETH symbol:", mockVETH.symbol());
        console.log("MockVETH decimals:", mockVETH.decimals());

        // Mint initial supply to deployer
        uint256 initialUSDCSupply = 1_000_000 * 10**mockUSDC.decimals(); // 1M USDC
        uint256 initialVETHSupply = 1_000 * 10**mockVETH.decimals();     // 1K vETH

        mockUSDC.mint(msg.sender, initialUSDCSupply);
        mockVETH.mint(msg.sender, initialVETHSupply);

        console.log("Initial USDC minted:", initialUSDCSupply);
        console.log("Initial vETH minted:", initialVETHSupply);
        console.log("Tokens minted to deployer:", msg.sender);

        vm.stopBroadcast();

        // Log deployment summary
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("MockUSDC: ", address(mockUSDC));
        console.log("MockVETH: ", address(mockVETH));
        console.log("Deployer: ", msg.sender);
        console.log("=========================");
    }
}
