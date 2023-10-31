// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {PoolModifyPositionTest} from "@uniswap/v4-core/contracts/test/PoolModifyPositionTest.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/contracts/interfaces/IHooks.sol"; //add this to the snippets (REMOVE WHEN ADDED)


contract CreateLiquidityExampleInputs {
    using CurrencyLibrary for Currency;

    // set the router address
    PoolModifyPositionTest lpRouter = new PoolModifyPositionTest(IPoolManager(0x0DCd1Bf9A1b36cE34237eEaFef220932846BCD82));

    function run() external {
        address token0 = address(0x4ed7c70F96B99c776995fB64377f0d4aB3B0e1C1);//mUSDC deployed locally, you paste your contract here for deploying
        address token1 = address(0x59b670e9fA9D0A427751Af201D676719a970857b);//mUNI deployed locally, you paste your contract here for deploying

        // Using a hookless pool
        PoolKey memory pool = PoolKey({
            currency0: Currency.wrap(token0), //update to wrap
            currency1: Currency.wrap(token1), //update to wrap
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0x3cC6198C897c87353Cb89bCCBd9b5283A0042a14))
        });

        // approve tokens to the LP Router
        IERC20(token0).approve(address(lpRouter), type(uint256).max);
        IERC20(token1).approve(address(lpRouter), type(uint256).max);

        // Provide 10e18 worth of liquidity on the range of [-600, 600]

        lpRouter.modifyPosition(pool, IPoolManager.ModifyPositionParams(-600, 600, 1 ether), abi.encode(msg.sender));
    }
}
