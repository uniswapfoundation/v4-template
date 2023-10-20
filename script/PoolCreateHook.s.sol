// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolManager} from "@uniswap/v4-core/contracts/PoolManager.sol";
import {IHooks} from "@uniswap/v4-core/contracts/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/contracts/types/PoolId.sol";


contract PoolInitializeExampleInputs {
    using CurrencyLibrary for Currency;

    // set the pool manager address
    IPoolManager manager = IPoolManager(0x0DCd1Bf9A1b36cE34237eEaFef220932846BCD82);

    // / @notice Initialize a pool with a custom hook:
    // /     0.30% swap fee
    // /     tick spacing of 60
    // /     starting price of 1:1
    // /     hook's beforeInitialize() requires providing a timestamp
    function run() external {
        address hook = address(0x3cC6198C897c87353Cb89bCCBd9b5283A0042a14); // prefix indicates the hook only has a beforeInitialize() function
        address token0 = address(0x4ed7c70F96B99c776995fB64377f0d4aB3B0e1C1);//usdc deploy locally
        address token1 = address(0x59b670e9fA9D0A427751Af201D676719a970857b);//uni deployed locally
        uint24 swapFee = 4000;
        int24 tickSpacing = 60;

        // floor(sqrt(1) * 2^96)
        uint160 startingPrice = 79228162514264337593543950336;

        // Assume the custom hook requires a timestamp when initializing it
        bytes memory hookData = abi.encode(block.timestamp);

        PoolKey memory pool = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: swapFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hook)
        });

        //Turn the Pool into an ID so you can use it for modifying positions, swapping, etc.
        PoolId id = PoolIdLibrary.toId(pool);
        bytes32 idBytes = PoolId.unwrap(id);

        console.log("Pool ID Below");
        console.logBytes32(bytes32(idBytes));

        // Emit the pool ID so you can easily find it in the logs
        manager.initialize(pool, startingPrice, hookData);
    }
}
