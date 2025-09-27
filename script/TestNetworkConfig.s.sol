// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";

/// @title Test Network Configuration
/// @notice Quick test to verify network-specific Pyth configurations
contract TestNetworkConfigScript is Script {
    // Network-specific Pyth contract addresses
    mapping(string => address) public pythContracts;
    
    // ETH/USD Pyth Price Feed ID (same across all networks)
    bytes32 public constant ETH_USD_FEED_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    
    string public deploymentNetwork;
    
    function setUp() public {
        // Try to get deployment network from environment, default to "anvil"
        try vm.envString("DEPLOYMENT_NETWORK") returns (string memory network) {
            deploymentNetwork = network;
        } catch {
            deploymentNetwork = "anvil";
        }
        
        // Configure Pyth contract addresses per network
        pythContracts["anvil"] = address(0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF); // Placeholder for local testing
        pythContracts["sepolia"] = 0xDd24F84d36BF92C65F92307595335bdFab5Bbd21; // Pyth Sepolia testnet
        pythContracts["mainnet"] = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6; // Pyth Ethereum mainnet
        pythContracts["arbitrum"] = 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C; // Pyth Arbitrum
        pythContracts["arbitrum-sepolia"] = 0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF; // Pyth Arbitrum Sepolia
        pythContracts["polygon"] = 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C; // Pyth Polygon
        pythContracts["base"] = 0x8250f4aF4B972684F7b336503E2D6dFeDeB1487a; // Pyth Base
        pythContracts["optimism"] = 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C; // Pyth Optimism
    }
    
    /// @notice Get the Pyth contract address for the current deployment network
    function getPythContract() internal view returns (address) {
        address pythAddress = pythContracts[deploymentNetwork];
        require(pythAddress != address(0), string(abi.encodePacked("Pyth contract not configured for network: ", deploymentNetwork)));
        return pythAddress;
    }
    
    function run() external view {
        console.log("==============================================");
        console.log("NETWORK CONFIGURATION TEST");
        console.log("==============================================");
        console.log("Current Network:", deploymentNetwork);
        console.log("Pyth Contract:", getPythContract());
        console.log("ETH/USD Feed ID:", vm.toString(ETH_USD_FEED_ID));
        console.log("==============================================");
        
        // Test all networks
        console.log("\nSupported Networks:");
        console.log("anvil:           ", pythContracts["anvil"]);
        console.log("sepolia:         ", pythContracts["sepolia"]);
        console.log("mainnet:         ", pythContracts["mainnet"]);
        console.log("arbitrum:        ", pythContracts["arbitrum"]);
        console.log("arbitrum-sepolia:", pythContracts["arbitrum-sepolia"]);
        console.log("polygon:         ", pythContracts["polygon"]);
        console.log("base:            ", pythContracts["base"]);
        console.log("optimism:        ", pythContracts["optimism"]);
        console.log("==============================================");
    }
}
