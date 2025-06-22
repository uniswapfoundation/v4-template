// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {ParameterBuilder} from "../utils/ParameterBuilder.sol";
import {CalldataEncoder} from "../utils/CalldataEncoder.sol";
import {TokenApprover} from "../utils/TokenApprover.sol";
import {PoolInputs, PositionInputs, CurrencyPair} from "../types/Types.sol";

/// @dev Creates a pool and adds initial liquidity in a single, atomic transaction.
library BootstrapPool {
    function run(
        IPermit2 permit2,
        IPositionManager positionManager,
        CurrencyPair memory currencyPair,
        IHooks hooks,
        PoolInputs memory poolInputs,
        PositionInputs memory positionInputs,
        address deployer
    ) internal {
        require(
            Currency.unwrap(currencyPair.currency0) != Currency.unwrap(currencyPair.currency1),
            "Token addresses should not match."
        );
        require(
            uint160(Currency.unwrap(currencyPair.currency0)) < uint160(Currency.unwrap(currencyPair.currency1)),
            "Token addresses should be numerically sorted."
        );

        // Compose position params
        (PoolKey memory poolKey, uint128 liquidity, int24 tickLower, int24 tickUpper) = ParameterBuilder
            .buildPositionParams(currencyPair.currency0, currencyPair.currency1, hooks, poolInputs, positionInputs);
        // Encode position params
        (bytes memory actions, bytes[] memory params) = CalldataEncoder.encodeModifyLiquidityParams(
            poolKey,
            tickLower,
            tickUpper,
            liquidity,
            deployer,
            positionInputs.amount0Max,
            positionInputs.amount1Max,
            positionInputs.hookData
        );
        // Encode multicall
        (bytes[] memory multicallData) = CalldataEncoder.encodeCreateAndMintMulticall(
            positionManager,
            poolKey,
            poolInputs.startingPrice,
            actions,
            params,
            positionInputs.deadline,
            positionInputs.hookData
        );

        // Give PositionManager unlimited approval
        TokenApprover.approveUnlimited(permit2, currencyPair.currency0, address(positionManager));
        TokenApprover.approveUnlimited(permit2, currencyPair.currency1, address(positionManager));
        // Multicall
        // If the pool is an eth pair, native tokens need to be transferred
        positionManager.multicall{value: currencyPair.currency0.isAddressZero() ? positionInputs.amount0Max : 0}(
            multicallData
        );
    }
}
