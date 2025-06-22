// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolInputs, CurrencyPair} from "../types/Types.sol";

/// @dev Creates pool only
library CreatePool {
    function run(IPoolManager poolManager, PoolInputs memory poolInputs, CurrencyPair memory currencyPair, IHooks hooks)
        internal
    {
        require(
            Currency.unwrap(currencyPair.currency0) != Currency.unwrap(currencyPair.currency1),
            "Token addresses should not match."
        );
        require(
            uint160(Currency.unwrap(currencyPair.currency0)) < uint160(Currency.unwrap(currencyPair.currency1)),
            "Token addresses should be numerically sorted."
        );

        PoolKey memory poolKey =
            PoolKey(currencyPair.currency0, currencyPair.currency1, poolInputs.lpFee, poolInputs.tickSpacing, hooks);
        poolManager.initialize(poolKey, poolInputs.startingPrice);
    }
}
