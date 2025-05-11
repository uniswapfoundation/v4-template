// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

/**
 * @title SimpleAddLiquidity
 * @notice Ultra minimal script to check token balances
 */
contract SimpleAddLiquidity is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address vcopAddress = vm.envAddress("VCOP_ADDRESS");
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Check balances
        IERC20 vcop = IERC20(vcopAddress);
        IERC20 usdc = IERC20(usdcAddress);
        
        uint256 vcopBalance = vcop.balanceOf(msg.sender);
        uint256 usdcBalance = usdc.balanceOf(msg.sender);
        
        console.log("VCOP address:", vcopAddress);
        console.log("USDC address:", usdcAddress);
        console.log("VCOP balance:", vcopBalance);
        console.log("USDC balance:", usdcBalance);
        
        vm.stopBroadcast();
    }
} 