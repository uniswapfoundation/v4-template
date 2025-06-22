// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolInputs, PositionInputs} from "../types/Types.sol";

/// @dev Provides helper functions to build the necessary parameters for Uniswap V4 positions.
library ParameterBuilder {
    /// @dev Calculates the final liquidity parameters for a position based on user inputs
    function buildPositionParams(
        Currency currency0,
        Currency currency1,
        IHooks hooks,
        PoolInputs memory poolInputs,
        PositionInputs memory positionInputs
    ) internal pure returns (PoolKey memory poolKey, uint128 liquidity, int24 tickLower, int24 tickUpper) {
        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: poolInputs.lpFee,
            tickSpacing: poolInputs.tickSpacing,
            hooks: hooks
        });

        // Snap the ticks to the nearest valid tick spacing
        tickLower = (positionInputs.tickLower / poolInputs.tickSpacing) * poolInputs.tickSpacing;
        tickUpper = (positionInputs.tickUpper / poolInputs.tickSpacing) * poolInputs.tickSpacing;

        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            poolInputs.startingPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            positionInputs.token0Amount,
            positionInputs.token1Amount
        );
    }
}
