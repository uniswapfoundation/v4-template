// SPDX-License-Identifier: MIT
// OpenZeppelin Uniswap Hooks (last updated v0.1.0) (src/base/BaseAsyncSwap.sol)

pragma solidity ^0.8.24;

import {BaseHook} from "src/base/BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {CurrencySettler} from "src/utils/CurrencySettler.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {IHookEvents} from "src/interfaces/IHookEvents.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";

/**
 * @dev Base implementation for async swaps, which skip the v3-like swap implementation of the `PoolManager`
 * by taking the full swap input amount and returning a delta that nets out the specified amount to 0.
 *
 * This base hook allows developers to implement arbitrary logic to handle swaps, including use-cases like
 * asynchronous swaps and custom swap-ordering. However, given this flexibility, developers should ensure
 * that any logic implemented interacts safely with the `PoolManager` and works correctly.
 *
 * In order to handle async swaps, the hook mints ERC-6909 claim tokens for the specified currency and amount.
 * Inheriting contracts are free to handle these claim tokens as necessary, which can be redeemed for the
 * underlying currency by using the `settle` function from the `CurrencySettler` library.
 *
 * IMPORTANT: If the hook is used for multiple pools, the ERC-6909 tokens must be separated and managed
 * independently for each pool in order to prevent draining of ERC-6909 tokens from one pool to another.
 *
 * NOTE: The hook only supports async exact-input swaps. Exact-output swaps will be processed normally
 * by the `PoolManager`.
 *
 * WARNING: This is experimental software and is provided on an "as is" and "as available" basis. We do
 * not give any warranties and will not be liable for any losses incurred through any use of this code
 * base.
 *
 * _Available since v0.1.0_
 */
abstract contract BaseAsyncSwap is BaseHook, IHookEvents {
    using SafeCast for uint256;
    using CurrencySettler for Currency;

    /**
     * @dev Set the `PoolManager` address.
     */
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    /**
     * @dev Skip the v3-like swap implementation of the `PoolManager` by returning a delta that nets out the
     * specified amount to 0 to enable asynchronous swaps.
     */
    function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal
        virtual
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Async swaps are only possible on exact-input swaps, so exact-output swaps are executed by the `PoolManager` as normal
        if (params.amountSpecified < 0) {
            // Determine which currency is specified
            Currency specified = params.zeroForOne ? key.currency0 : key.currency1;

            // Get the positive specified amount
            uint256 specifiedAmount = uint256(-params.amountSpecified);

            // Mint ERC-6909 claim token for the specified currency and amount
            specified.take(poolManager, address(this), specifiedAmount, true);

            // Calculate the fee amount for the swap, paid to LPs
            uint256 feeAmount = _calculateSwapFee(key, specifiedAmount);

            // Emit the swap event with the specified amount signifying the amount taken by the hook
            if (specified == key.currency0) {
                emit HookSwap(
                    PoolId.unwrap(key.toId()), sender, specifiedAmount.toInt128(), 0, feeAmount.toUint128(), 0
                );
            } else {
                emit HookSwap(
                    PoolId.unwrap(key.toId()), sender, 0, specifiedAmount.toInt128(), 0, feeAmount.toUint128()
                );
            }

            // Return delta that nets out specified amount to 0.
            return (this.beforeSwap.selector, toBeforeSwapDelta(specifiedAmount.toInt128(), 0), 0);
        } else {
            return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }
    }

    /**
     * @dev Calculate the fee amount for the swap.
     *
     * @param key The pool key.
     * @param specifiedAmount The specified amount of the swap.
     *
     * @return feeAmount The fee amount for the swap.
     */
    function _calculateSwapFee(PoolKey calldata key, uint256 specifiedAmount)
        internal
        virtual
        returns (uint256 feeAmount)
    {
        return 0;
    }

    /**
     * @dev Set the hook permissions, specifically `beforeSwap` and `beforeSwapReturnDelta`.
     *
     * @return permissions The hook permissions.
     */
    function getHookPermissions() public pure virtual override returns (Hooks.Permissions memory permissions) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
}
