// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Counter} from "../../src/Counter.sol";

/// @dev Mines the address and deploys a hook contract.
library DeployHooks {
    function run(IPoolManager poolManager, address deployer) internal returns (IHooks hooks) {
        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
        );

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(poolManager);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(deployer, flags, type(Counter).creationCode, constructorArgs);

        // Deploy the hook using CREATE2
        hooks = new Counter{salt: salt}(poolManager);
        require(address(hooks) == hookAddress, "DeployHookScript: Hook Address Mismatch");
    }
}
