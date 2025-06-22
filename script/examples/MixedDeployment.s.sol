// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolInputs, CurrencyPair} from "../types/Types.sol";
import {LoadDependencies} from "../actions/LoadDependencies.sol";
import {CreatePool} from "../actions/CreatePool.sol";

/// @dev Example mixed task usage - Create a new (unrealistic) ETH/USDC pool
contract MixedDeploymentScript is Script {
    // Tokens
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant ETH = address(0);
    /// Currency pair (ensure numerically sorted)
    CurrencyPair public currencyPair = CurrencyPair(Currency.wrap(ETH), Currency.wrap(USDC));
    /// Pool configuration
    PoolInputs public poolInputs = PoolInputs({
        lpFee: 70_000, // 7%
        tickSpacing: 200,
        // Assume ETH is 2500.
        startingPrice: uint160(Math.sqrt(2500) * 2 ** 96)
    });

    function run() public {
        vm.startBroadcast();

        // Label tokens
        vm.label(Currency.unwrap(currencyPair.currency0), "Token0/ETH");
        vm.label(Currency.unwrap(currencyPair.currency1), "Token1/USDC");
        /// -- 00 -- Load dependencies for network
        (, IPoolManager poolManager,,) = LoadDependencies.run();
        // Label
        vm.label(address(poolManager), "PoolManager");
        /// -- 03b -- Create pool
        CreatePool.run(poolManager, poolInputs, currencyPair, IHooks(address(0)));

        vm.stopBroadcast();
    }
}
