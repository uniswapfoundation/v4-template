// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {VCOPCollateralized} from "../src/VcopCollateral/VCOPCollateralized.sol";

/**
 * @title UpdatePermissionsScript
 * @notice Script to update burning permissions for the hook
 * @dev Run with: forge script script/UpdatePermissions.s.sol:UpdatePermissionsScript --broadcast --rpc-url https://sepolia.base.org
 */
contract UpdatePermissionsScript is Script {
    address constant VCOP_ADDRESS = 0x97CBc4fB89a85681b5f2da1c5569b7938ff8bFa3;
    address constant HOOK_ADDRESS = 0x07CFb798c049E71F8D140AEE17c1DE2e647Dc4c0;

    function run() public returns (bool) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        console.log("=== Updating VCOP Token Permissions ===");
        console.log("Deployer address:", deployerAddress);
        console.log("VCOP address:", VCOP_ADDRESS);
        console.log("Hook address:", HOOK_ADDRESS);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Verify deployer is the owner of VCOP
        VCOPCollateralized vcop = VCOPCollateralized(VCOP_ADDRESS);
        address owner = vcop.owner();
        console.log("Current VCOP owner:", owner);
        
        if (owner != deployerAddress) {
            console.log("ERROR: Deployer is not the owner of VCOP token");
            console.log("Current owner:", owner);
            console.log("Deployer:", deployerAddress);
            return false;
        }
        
        // Check current burn permissions
        bool canBurn = vcop.burners(HOOK_ADDRESS);
        console.log("Hook currently has burn permission:", canBurn);
        
        if (canBurn) {
            console.log("Hook already has burn permission, no action needed");
        } else {
            // Grant burn permissions to hook
            vcop.setBurner(HOOK_ADDRESS, true);
            console.log("Burn permission granted to hook");
            
            // Verify the permission was set
            bool newPermission = vcop.burners(HOOK_ADDRESS);
            console.log("Hook now has burn permission:", newPermission);
        }
        
        vm.stopBroadcast();
        
        console.log("=== Permission update complete ===");
        return true;
    }
} 