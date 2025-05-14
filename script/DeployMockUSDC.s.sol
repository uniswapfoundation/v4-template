// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import "forge-std/console2.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/**
 * @title DeployMockUSDC
 * @notice Script to deploy a token that simulates USDC for testing
 * Used before the main deployment to create a complete test environment
 */
contract DeployMockUSDC is Script {
    // Constants
    uint8 constant USDC_DECIMALS = 6;
    uint256 constant INITIAL_SUPPLY = 10_000_000 * 6**USDC_DECIMALS; // 10,000,000 USDC

    function run() public returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        console2.log("=== Deploying Mock USDC ===");
        console2.log("Deployer address:", deployerAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy MockUSDC token with 6 decimals
        MockERC20 mockUSDC = new MockERC20("USD Coin", "USDC", USDC_DECIMALS);
        
        // Mint initial supply to the deployer
        mockUSDC.mint(deployerAddress, INITIAL_SUPPLY);
        
        vm.stopBroadcast();
        
        console2.log("Mock USDC deployed at:", address(mockUSDC));
        console2.log("Initial supply:", INITIAL_SUPPLY / 10**USDC_DECIMALS, "USDC");
        
        // Save the address in an environment variable for later use
        vm.setEnv("MOCK_USDC_ADDRESS", vm.toString(address(mockUSDC)));
        
        return address(mockUSDC);
    }
} 