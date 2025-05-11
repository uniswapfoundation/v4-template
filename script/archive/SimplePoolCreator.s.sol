// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

/**
 * @title SimplePoolCreator
 * @notice Ultra minimal script to create a pool using PoolManager directly
 */
contract SimplePoolCreator is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        address vcopAddress = vm.envAddress("VCOP_ADDRESS");
        address hookAddress = vm.envAddress("HOOK_ADDRESS");
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // References
        IPoolManager poolManager = IPoolManager(poolManagerAddress);
        
        // Parameters
        uint24 fee = 3000; // 0.3%
        int24 tickSpacing = 60;
        uint160 sqrtPriceX96 = 79228162514264337593543950336; // sqrt(1) * 2^96
        
        // Create currencies
        Currency currency0;
        Currency currency1;
        
        if (vcopAddress < usdcAddress) {
            currency0 = Currency.wrap(vcopAddress);
            currency1 = Currency.wrap(usdcAddress);
            console.log("VCOP is token0");
        } else {
            currency0 = Currency.wrap(usdcAddress);
            currency1 = Currency.wrap(vcopAddress);
            console.log("USDC is token0");
        }
        
        // Create pool key
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hookAddress)
        });
        
        // Initialize pool directly with pool manager
        poolManager.initialize(key, sqrtPriceX96);
        
        console.log("Pool created successfully");
        
        vm.stopBroadcast();
    }
} 