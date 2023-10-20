// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolManager} from "@uniswap/v4-core/contracts/PoolManager.sol";
import {IHooks} from "@uniswap/v4-core/contracts/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {PoolId} from "@uniswap/v4-core/contracts/types/PoolId.sol";


contract PoolInitializeExampleInputs {
    using CurrencyLibrary for Currency;

    // set the pool manager address
    IPoolManager manager = IPoolManager(0x0DCd1Bf9A1b36cE34237eEaFef220932846BCD82);

    event Initialize(
        PoolId indexed id,
        Currency indexed currency0,
        Currency indexed currency1,
        uint24 fee,
        int24 tickSpacing,
        IHooks hooks
    );


    // 0x3c8B37Cb343Da423aCd0634B9Da6e247219AaDc7

    // / @notice Initialize a hookless pool:
    // /     0.05% swap fee
    // /     tick spacing of 10
    // /     starting price of 1:1
    function run() external {
        address token0 = address(0x4ed7c70F96B99c776995fB64377f0d4aB3B0e1C1);//usdc deploy locally
        address token1 = address(0x59b670e9fA9D0A427751Af201D676719a970857b);//uni deployed locally
        uint24 swapFee = 500;
        int24 tickSpacing = 10;

        // floor(sqrt(1) * 2^96)
        uint160 startingPrice = 79228162514264337593543950336;

        // hookless pool doesnt expect any initialization data
        bytes memory hookData = new bytes(0);

        PoolKey memory pool = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: swapFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(0x0))
        });
        manager.initialize(pool, startingPrice, hookData);
    }

    // / @notice Initialize a pool with a custom hook:
    // /     0.30% swap fee
    // /     tick spacing of 60
    // /     starting price of 1:1
    // /     hook's beforeInitialize() requires providing a timestamp
}
