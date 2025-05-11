// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {VCOPRebased} from "../src/VCOPRebased.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/**
 * @title TransferVCOPToWallet
 * @notice Script to transfer 100 VCOP tokens to the wallet if needed
 */
contract TransferVCOPToWallet is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address vcopAddress = vm.envAddress("VCOP_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Get the VCOP token instance
        VCOPRebased vcop = VCOPRebased(vcopAddress);
        
        // Check current balance
        uint256 currentBalance = vcop.balanceOf(msg.sender);
        console.log("Current VCOP balance:", currentBalance);
        
        // Amount to transfer - 100 VCOP (to ensure we have enough)
        uint256 amountToTransfer = 100 * 1e18;
        
        // The contract deployer should have plenty of tokens
        address contractDeployer = vcop.owner();
        uint256 deployerBalance = vcop.balanceOf(contractDeployer);
        console.log("Contract owner address:", contractDeployer);
        console.log("Contract owner balance:", deployerBalance);
        
        // We need enough VCOP for liquidity (at least 50 VCOP)
        if (currentBalance < 50 * 1e18 && deployerBalance >= amountToTransfer) {
            // Transfer VCOP tokens to our wallet from the contract owner
            // This requires us to be the owner or have the owner's private key
            if (contractDeployer == msg.sender) {
                // We are the owner, so we can transfer directly
                vcop.transfer(msg.sender, amountToTransfer);
                console.log("Transferred", amountToTransfer, "VCOP tokens to wallet");
            } else {
                console.log("WARNING: Cannot transfer tokens. You are not the contract owner.");
                console.log("Please ask the contract owner to send you some VCOP tokens.");
            }
        } else if (currentBalance >= 50 * 1e18) {
            console.log("You already have enough VCOP tokens for providing liquidity.");
        } else {
            console.log("WARNING: Contract owner doesn't have enough tokens to transfer.");
        }
        
        // Check new balance
        uint256 newBalance = vcop.balanceOf(msg.sender);
        console.log("New VCOP balance:", newBalance);
        
        vm.stopBroadcast();
    }
} 