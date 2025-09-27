// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {MockUSDC} from "../test/utils/mocks/MockUSDC.sol";
import {MockVETH} from "../test/utils/mocks/MockVETH.sol";

/// @notice Mints additional tokens to specified addresses
contract MintTokensScript is Script {
    /////////////////////////////////////
    // --- Configure These ---
    /////////////////////////////////////
    
    // Token contract addresses (update these after deployment)
    address constant MOCK_USDC_ADDRESS = address(0); // Update this
    address constant MOCK_VETH_ADDRESS = address(0); // Update this
    
    // Mint amounts
    uint256 constant USDC_MINT_AMOUNT = 100_000 * 1e6;  // 100K USDC
    uint256 constant VETH_MINT_AMOUNT = 100 * 1e18;     // 100 vETH
    
    // Recipients (update these as needed)
    address[] recipients = [
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, // Anvil account #0
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8, // Anvil account #1
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC  // Anvil account #2
    ];
    
    /////////////////////////////////////

    function run() public {
        require(MOCK_USDC_ADDRESS != address(0), "Update MOCK_USDC_ADDRESS");
        require(MOCK_VETH_ADDRESS != address(0), "Update MOCK_VETH_ADDRESS");

        MockUSDC mockUSDC = MockUSDC(MOCK_USDC_ADDRESS);
        MockVETH mockVETH = MockVETH(MOCK_VETH_ADDRESS);

        vm.startBroadcast();

        console.log("Minting tokens to recipients...");
        console.log("USDC amount per recipient:", USDC_MINT_AMOUNT);
        console.log("vETH amount per recipient:", VETH_MINT_AMOUNT);

        for (uint256 i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];
            
            // Mint USDC
            mockUSDC.mint(recipient, USDC_MINT_AMOUNT);
            console.log("Minted USDC to:", recipient);
            
            // Mint vETH
            mockVETH.mint(recipient, VETH_MINT_AMOUNT);
            console.log("Minted vETH to:", recipient);
        }

        vm.stopBroadcast();

        console.log("\n=== MINTING SUMMARY ===");
        console.log("Recipients:", recipients.length);
        console.log("Total USDC minted:", USDC_MINT_AMOUNT * recipients.length);
        console.log("Total vETH minted:", VETH_MINT_AMOUNT * recipients.length);
        console.log("======================");
    }

    /// @notice Mint tokens to a specific address with custom amounts
    /// @dev Call this function directly with custom parameters
    function mintToAddress(
        address usdcAddress,
        address vethAddress,
        address recipient,
        uint256 usdcAmount,
        uint256 vethAmount
    ) public {
        MockUSDC mockUSDC = MockUSDC(usdcAddress);
        MockVETH mockVETH = MockVETH(vethAddress);

        vm.startBroadcast();

        if (usdcAmount > 0) {
            mockUSDC.mint(recipient, usdcAmount);
            console.log("Minted USDC:", usdcAmount, "to:", recipient);
        }

        if (vethAmount > 0) {
            mockVETH.mint(recipient, vethAmount);
            console.log("Minted vETH:", vethAmount, "to:", recipient);
        }

        vm.stopBroadcast();
    }
}
