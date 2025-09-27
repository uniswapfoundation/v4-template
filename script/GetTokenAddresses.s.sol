// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

/// @notice Helper script to get deployed token addresses for BaseScript configuration
contract GetTokenAddressesScript is Script {
    
    /////////////////////////////////////
    // --- Update These After Deployment ---
    /////////////////////////////////////
    
    address constant MOCK_USDC_ADDRESS = address(0); // Update this after deploying
    address constant MOCK_VETH_ADDRESS = address(0); // Update this after deploying
    
    /////////////////////////////////////

    function run() public pure {
        console.log("=== TOKEN ADDRESSES FOR BaseScript.sol ===");
        console.log("");
        
        if (MOCK_USDC_ADDRESS != address(0)) {
            console.log("// Update these addresses in script/base/BaseScript.sol");
            console.log("IERC20 internal constant token0 = IERC20(%s);", addressToString(MOCK_USDC_ADDRESS));
            console.log("IERC20 internal constant token1 = IERC20(%s);", addressToString(MOCK_VETH_ADDRESS));
        } else {
            console.log("WARNING: Please update MOCK_USDC_ADDRESS and MOCK_VETH_ADDRESS in this script");
            console.log("   after deploying the tokens, then run this script again.");
        }
        
        console.log("");
        console.log("===========================================");
    }
    
    function addressToString(address addr) internal pure returns (string memory) {
        bytes memory data = abi.encodePacked(addr);
        bytes memory alphabet = "0123456789abcdef";
        
        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = "0";
        str[1] = "x";
        
        for (uint256 i = 0; i < data.length; i++) {
            str[2 + i * 2] = alphabet[uint8(data[i] >> 4)];
            str[3 + i * 2] = alphabet[uint8(data[i] & 0x0f)];
        }
        
        return string(str);
    }
}
