// SPDX-License-Identifier: MIT
// OpenZeppelin Uniswap Hooks (last updated v0.1.0) (src/base/BaseCustomCurve.sol)

pragma solidity ^0.8.24;

import {BaseHook} from "uniswap-hooks/base/BaseHook.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {CurrencySettler} from "uniswap-hooks/utils/CurrencySettler.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {BalanceDelta, toBalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";

/// @dev experimental alternative to OZ BaseCustomCurve
abstract contract MyCustomCurve is BaseHook, IUnlockCallback {
    using CurrencySettler for Currency;
    using SafeCast for uint256;

    /**
     * @dev Set the pool `PoolManager` address.
     */
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    /**
     * @dev Overides the default swap logic of the `PoolManager` and calls the {_getUnspecifiedAmount}
     * to get the amount of tokens to be sent to the receiver.
     *
     * NOTE: In order to take and settle tokens from the pool, the hook must hold the liquidity added
     * via the {addLiquidity} function.
     */
    function _beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        internal
        virtual
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Determine if the swap is exact input or exact output
        bool exactInput = params.amountSpecified < 0;
        bool zeroForOne = params.zeroForOne;

        // Determine which currency is specified and which is unspecified
        (Currency specified, Currency unspecified) =
            (zeroForOne == exactInput) ? (key.currency0, key.currency1) : (key.currency1, key.currency0);

        // Get the positive specified amount
        uint256 specifiedAmount = exactInput ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);

        // Get the amount of the unspecified currency to be taken or settled
        uint256 unspecifiedAmount = _getUnspecifiedAmount(key, zeroForOne, exactInput, specifiedAmount);

        // New delta must be returned, so store in memory
        BeforeSwapDelta returnDelta;

        if (exactInput) {
            // For exact input swaps:
            // 1. Take the specified input (user-given) amount from this contract's balance in the pool
            specified.take(poolManager, address(this), specifiedAmount, true);
            // 2. Send the calculated output amount to this contract's balance in the pool
            unspecified.settle(poolManager, address(this), unspecifiedAmount, true);

            returnDelta = toBeforeSwapDelta(specifiedAmount.toInt128(), -unspecifiedAmount.toInt128());
        } else {
            // For exact output swaps:
            // 1. Take the calculated input amount from this contract's balance in the pool
            unspecified.take(poolManager, address(this), unspecifiedAmount, true);
            // 2. Send the specified (user-given) output amount to this contract's balance in the pool
            specified.settle(poolManager, address(this), specifiedAmount, true);

            returnDelta = toBeforeSwapDelta(-specifiedAmount.toInt128(), unspecifiedAmount.toInt128());
        }

        return (this.beforeSwap.selector, returnDelta, 0);
    }

    /// @notice a utility function to add or remove capital from the hook
    /// @dev when adding liquidity, ERC20s are transferred to the PoolManager and the hook custodies ERC6909
    /// @dev when removing liquidity, ERC20s are transferred to a recipient, and the hook burns ERC6909
    function _addOrRemove(Currency currency0, Currency currency1, BalanceDelta amounts, address user)
        internal
        virtual
        returns (bytes memory)
    {
        return poolManager.unlock(abi.encode(currency0, currency1, amounts, user));
    }

    /**
     * @dev Decodes the callback data and applies the liquidity modifications, overriding the custom
     * accounting logic to mint and burn ERC-6909 claim tokens which are used in swaps.
     *
     * @param rawData The callback data encoded in the {_modifyLiquidity} function.
     * @return returnData The encoded caller and fees accrued deltas.
     */
    function unlockCallback(bytes calldata rawData)
        external
        virtual
        override
        onlyPoolManager
        returns (bytes memory returnData)
    {
        // user is the payer or the recipient of the balance delta
        (Currency currency0, Currency currency1, BalanceDelta amounts, address user) =
            abi.decode(rawData, (Currency, Currency, BalanceDelta, address));

        // Handle currency0
        // remove liquidity (sending ERC20 to user) when delta is positive
        if (0 < amounts.amount0()) {
            // send ERC20 to the user
            currency0.take(poolManager, user, uint256(int256(amounts.amount0())), false);

            // burn the ERC-6909 tokens
            currency0.settle(poolManager, address(this), uint256(int256(amounts.amount0())), true);
        }
        // adding liquidity (user paying ERC20) when delta is negative
        else if (amounts.amount0() < 0) {
            // take ERC20 from the user
            currency0.settle(poolManager, user, uint256(-int256(amounts.amount0())), false);

            // mint ERC-6909 to the hook
            currency0.take(poolManager, address(this), uint256(-int256(amounts.amount0())), true);
        }

        // Handle currency1
        // remove liquidity (sending ERC20 to user) when delta is positive
        if (0 < amounts.amount1()) {
            // send ERC20 to the user
            currency1.take(poolManager, user, uint256(int256(amounts.amount1())), false);

            // burn the ERC-6909 tokens
            currency1.settle(poolManager, address(this), uint256(int256(amounts.amount1())), true);
        }
        // adding liquidity (user paying ERC20) when delta is negative
        else if (amounts.amount1() < 0) {
            // take ERC20 from the user
            currency1.settle(poolManager, user, uint256(-int256(amounts.amount1())), false);

            // mint ERC-6909 to the hook
            currency1.take(poolManager, address(this), uint256(-int256(amounts.amount1())), true);
        }

        return "";
    }

    function _getUnspecifiedAmount(PoolKey calldata key, bool zeroForOne, bool exactInput, uint256 specifiedAmount)
        internal
        virtual
        returns (uint256 unspecifiedAmount);

    /**
     * @dev Set the hook permissions, specifically `beforeInitialize`, `beforeAddLiquidity`, `beforeRemoveLiquidity`,
     * `beforeSwap`, and `beforeSwapReturnDelta`
     *
     * @return permissions The hook permissions.
     */
    function getHookPermissions() public pure virtual override returns (Hooks.Permissions memory permissions) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: true,
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
