// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {PoolManager} from "@uniswap/v4-core/contracts/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolModifyPositionTest} from "@uniswap/v4-core/contracts/test/PoolModifyPositionTest.sol";
import {PoolSwapTest} from "@uniswap/v4-core/contracts/test/PoolSwapTest.sol";
import {PoolDonateTest} from "@uniswap/v4-core/contracts/test/PoolDonateTest.sol";
import {Counter} from "../src/Counter.sol";
import {CounterImplementation} from "../test/implementation/CounterImplementation.sol";

/// @notice Forge script for deploying v4 & hooks to **anvil**
/// @dev This script only works on an anvil RPC because v4 exceeds bytecode limits
/// @dev and we also need vm.etch() to deploy the hook to the proper address
contract CounterScript is Script {
    function setUp() public {}

    function run() public {
        vm.broadcast();
        PoolManager manager = new PoolManager(500000);

        // uniswap hook addresses must have specific flags encoded in the address
        // (attach 0x1 to avoid collisions with other hooks)
        uint160 targetFlags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | 0x1);

        // TODO: eventually use bytecode to deploy the hook with create2 to mine proper addresses
        // bytes memory hookBytecode = abi.encodePacked(type(Counter).creationCode, abi.encode(address(manager)));

        // TODO: eventually we'll want to use `uint160 salt` in the return create2 deploy the hook
        // (address hook,) = mineSalt(targetFlags, hookBytecode);
        // require(uint160(hook) & targetFlags == targetFlags, "CounterScript: could not find hook address");

        vm.broadcast();
        // until i figure out create2 deploys on an anvil RPC, we'll use the etch cheatcode
        CounterImplementation impl = new CounterImplementation(manager, Counter(address(targetFlags)));
        etchHook(address(impl), address(targetFlags));

        vm.startBroadcast();
        // Helpers for interacting with the pool
        new PoolModifyPositionTest(IPoolManager(address(manager)));
        new PoolSwapTest(IPoolManager(address(manager)));
        new PoolDonateTest(IPoolManager(address(manager)));
        vm.stopBroadcast();
    }

    function mineSalt(uint160 targetFlags, bytes memory creationCode)
        internal
        view
        returns (address hook, uint256 salt)
    {
        for (salt; salt < 100; salt++) {
            hook = _getAddress(salt, creationCode);
            if (uint160(hook) & targetFlags == targetFlags) {
                break;
            }
        }
    }

    function _getAddress(uint256 salt, bytes memory creationCode) internal view returns (address) {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(creationCode)))))
        );
    }

    function etchHook(address _implementation, address _hook) internal {
        (, bytes32[] memory writes) = vm.accesses(_implementation);
        vm.etch(_hook, _implementation.code);
        // for each storage key that was written during the hook implementation, copy the value over
        unchecked {
            for (uint256 i = 0; i < writes.length; i++) {
                bytes32 slot = writes[i];
                vm.store(_hook, slot, vm.load(_implementation, slot));
            }
        }
    }
}
