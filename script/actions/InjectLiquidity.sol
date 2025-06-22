// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {ParameterBuilder} from "../utils/ParameterBuilder.sol";
import {CalldataEncoder} from "../utils/CalldataEncoder.sol";
import {TokenApprover} from "../utils/TokenApprover.sol";
import {PoolInputs, PositionInputs, CurrencyPair} from "../types/Types.sol";

/// @dev Adds liquidity only
library InjectLiquidity {
    using StateLibrary for IPoolManager;

    function run(
        IPermit2 permit2,
        IPoolManager poolManager,
        IPositionManager positionManager,
        CurrencyPair memory currencyPair,
        IHooks hooks,
        PoolInputs memory poolInputs,
        PositionInputs memory positionInputs
    ) internal {
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
        // Pool should already be deployed, deployed price takes priority
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolKey.toId());
        // Overwrite existing price
        poolInputs.startingPrice = sqrtPriceX96;
        // Compose position params
        (, uint128 liquidity, int24 tickLower, int24 tickUpper) = ParameterBuilder.buildPositionParams(
            currencyPair.currency0, currencyPair.currency1, hooks, poolInputs, positionInputs
        );
        // Encode position params
        (bytes memory actions, bytes[] memory params) = CalldataEncoder.encodeModifyLiquidityParams(
            poolKey,
            tickLower,
            tickUpper,
            liquidity,
            msg.sender,
            positionInputs.amount0Max,
            positionInputs.amount1Max,
            positionInputs.hookData
        );
        // If the pool is an eth pair, native tokens need to be transferred
        uint256 value = currencyPair.currency0.isAddressZero() ? positionInputs.amount0Max : 0;
        // Give PositionManager unlimited approval
        TokenApprover.approveUnlimited(permit2, currencyPair.currency0, address(positionManager));
        TokenApprover.approveUnlimited(permit2, currencyPair.currency1, address(positionManager));
        // Add liquidity
        positionManager.modifyLiquidities{value: value}(abi.encode(actions, params), positionInputs.deadline);
    }
}
