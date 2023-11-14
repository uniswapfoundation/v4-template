// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {PoolManager} from "@uniswap/v4-core/contracts/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolModifyPositionTest} from "@uniswap/v4-core/contracts/test/PoolModifyPositionTest.sol";
import {PoolSwapTest} from "@uniswap/v4-core/contracts/test/PoolSwapTest.sol";
import {PoolDonateTest} from "@uniswap/v4-core/contracts/test/PoolDonateTest.sol";
import {Counter} from "../src/Counter.sol";
import {HookMiner} from "../test/utils/HookMiner.sol";

/// @notice Forge script for deploying v4 & hooks to **anvil**
/// @dev This script only works on an anvil RPC because v4 exceeds bytecode limits
contract CounterScript is Script {
    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    function setUp() public {}

    function run() public {
        vm.broadcast();
        PoolManager manager = new PoolManager(500000);

        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_MODIFY_POSITION_FLAG
                | Hooks.AFTER_MODIFY_POSITION_FLAG
        );

        // Mine a salt that will produce a hook address with the correct flags
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(Counter).creationCode, abi.encode(address(manager)));

        // Deploy the hook using CREATE2
        vm.broadcast();
        Counter counter = new Counter{salt: salt}(IPoolManager(address(manager)));
        require(address(counter) == hookAddress, "CounterScript: hook address mismatch");

        // Additional helpers for interacting with the pool
        vm.startBroadcast();
        new PoolModifyPositionTest(IPoolManager(address(manager)));
        new PoolSwapTest(IPoolManager(address(manager)));
        new PoolDonateTest(IPoolManager(address(manager)));
        vm.stopBroadcast();
    }
}
