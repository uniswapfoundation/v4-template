// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

/// @dev Pairing of currencies used for liquidity functions
struct CurrencyPair {
    Currency currency0;
    Currency currency1;
}

/// @dev Inputs needed for creating or identifying a pool.
struct PoolInputs {
    uint24 lpFee;
    int24 tickSpacing;
    uint160 startingPrice;
}

/// @dev Inputs needed for defining a liquidity position's range and size.
struct PositionInputs {
    uint256 token0Amount;
    uint256 token1Amount;
    int24 tickLower;
    int24 tickUpper;
    uint256 amount0Max;
    uint256 amount1Max;
    uint256 deadline;
    bytes hookData;
}
