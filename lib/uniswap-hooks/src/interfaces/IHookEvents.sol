// SPDX-License-Identifier: MIT
// OpenZeppelin Uniswap Hooks (last updated v0.1.0) (src/interfaces/IHookEvents.sol)

pragma solidity ^0.8.24;

/**
 * @dev Interface for standard hook events emission.
 *
 * NOTE: Hooks should inherit from this interface to standardized event emission.
 */
interface IHookEvents {
    /**
     * @dev Emitted when a hook executes a swap outside of Uniswap's default concentrated liquidity AMM in a pool
     * identified by `poolId`, being `sender` the initiator of the swap, `amount0` and `amount1` the swap amounts
     * (positive for input, negative for output), and `hookLPfeeAmount0`, `hookLPfeeAmount1` the LP fees.
     */
    event HookSwap(
        bytes32 indexed poolId,
        address indexed sender,
        int128 amount0,
        int128 amount1,
        uint128 hookLPfeeAmount0,
        uint128 hookLPfeeAmount1
    );

    /**
     * @dev Emitted when a hook charges fees in a pool identified by `poolId`, being `sender` the initiator of the swap or
     * the liquidity modifier, `feeAmount0` and `feeAmount1` the fees charged in currency0 and currency1, defined by the `poolId`.
     */
    event HookFee(bytes32 indexed poolId, address indexed sender, uint128 feeAmount0, uint128 feeAmount1);

    /**
     * @dev Emitted when a liquidity modification is executed in a pool identified by `poolId`, being `sender` the liquidity modifier,
     * `amount0` and `amount1` the amounts added or removed in currency0 and currency1, defined by the `poolId`.
     */
    event HookModifyLiquidity(bytes32 indexed poolId, address indexed sender, int128 amount0, int128 amount1);

    /**
     * @dev Emitted when a bonus is added to an operation in a pool identified by `poolId`, being `amount0` and `amount1` the amounts
     * added in currency0 and currency1, defined by the `poolId`.
     */
    event HookBonus(bytes32 indexed poolId, uint128 amount0, uint128 amount1);
}
