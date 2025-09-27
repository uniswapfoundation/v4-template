// SPDX-License-Identifier: MIT
// OpenZeppelin Uniswap Hooks (last updated v1.1.0) (src/fee/BaseDynamicAfterFee.sol)

pragma solidity ^0.8.24;

import {BaseHook} from "src/base/BaseHook.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {CurrencySettler} from "src/utils/CurrencySettler.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {IHookEvents} from "src/interfaces/IHookEvents.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {TransientSlot} from "openzeppelin/utils/TransientSlot.sol";
import {SlotDerivation} from "openzeppelin/utils/SlotDerivation.sol";
import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";

/**
 * @dev Base implementation for dynamic target hook fees applied after swaps.
 *
 * Enables to enforce a dynamic target determined by {_getTargetUnspecified} for the unspecified currency of the swap
 * during {_beforeSwap}, where if the swap outcome results better than the target, any positive difference is taken
 * as a hook fee, being posteriorily handled or distributed by the hook via {_afterSwapHandler}.
 *
 * NOTE: In order to use this hook, the inheriting contract must implement {_getTargetUnspecified} to determine the target,
 * and {_afterSwapHandler} to handle accumulated fees.
 *
 * WARNING: This is experimental software and is provided on an "as is" and "as available" basis. We do
 * not give any warranties and will not be liable for any losses incurred through any use of this code
 * base.
 *
 * _Available since v0.1.0_
 */
abstract contract BaseDynamicAfterFee is BaseHook, IHookEvents {
    using TransientSlot for *;
    using SlotDerivation for *;
    using SafeCast for *;
    using CurrencySettler for Currency;

    /*
     * @dev The slot for the BaseDynamicAfterFee contract.
     * keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.BaseDynamicAfterFee")) - 1)) & ~bytes32(uint256(0xff))
    */
    bytes32 private constant BASE_DYNAMIC_AFTER_FEE_SLOT =
        0x573e65eb8119149aa4b92cb540f79645b8190fcaf67b1af773f62674fbe27900;

    /*
     * @dev The offset for the slot of the target unspecified amount.
    */
    uint256 private constant TARGET_UNSPECIFIED_AMOUNT_OFFSET = 0;

    /*
     * @dev The offset for the slot of the apply target boolean.
    */
    uint256 private constant APPLY_TARGET_OFFSET = 1;

    /**
     * @dev The target unspecified amount to be enforced by the `afterSwap` hook.
     */
    function _transientTargetUnspecifiedAmount() internal view returns (uint256) {
        return BASE_DYNAMIC_AFTER_FEE_SLOT.offset(TARGET_UNSPECIFIED_AMOUNT_OFFSET).asUint256().tload();
    }

    /**
     * @dev Whether the target unspecified amount should be enforced by the `afterSwap` hook.
     */
    function _transientApplyTarget() internal view returns (bool) {
        return BASE_DYNAMIC_AFTER_FEE_SLOT.offset(APPLY_TARGET_OFFSET).asBoolean().tload();
    }

    /**
     * @dev Set the target unspecified amount to be enforced by the `afterSwap` hook.
     */
    function _setTransientTargetUnspecifiedAmount(uint256 value) internal {
        BASE_DYNAMIC_AFTER_FEE_SLOT.offset(TARGET_UNSPECIFIED_AMOUNT_OFFSET).asUint256().tstore(value);
    }

    /**
     * @dev Set the apply flag to be used in the `afterSwap` hook.
     */
    function _setTransientApplyTarget(bool value) internal {
        BASE_DYNAMIC_AFTER_FEE_SLOT.offset(APPLY_TARGET_OFFSET).asBoolean().tstore(value);
    }

    /**
     * @dev Set the `PoolManager` address.
     */
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    /**
     * @dev Sets the target unspecified amount and apply flag to be used in the `afterSwap` hook.
     *
     * NOTE: The target unspecified amount and the apply flag are reset in the `afterSwap` hook.
     */
    function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        internal
        virtual
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Get and transiently store the target unspecified amount and the apply flag, overriding any previous values.
        (uint256 targetUnspecifiedAmount, bool applyTarget) = _getTargetUnspecified(sender, key, params, hookData);

        _setTransientTargetUnspecifiedAmount(targetUnspecifiedAmount);
        _setTransientApplyTarget(applyTarget);

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /**
     * @dev Enforce the target unspecified amount to the unspecified currency of the swap.
     *
     * When the swap is `exactInput` and the unspecified target is surpassed, the difference is decreased from the
     * output as a hook fee. Accordingly, when the swap is `exactOutput` and the unspecified target is not reached, the
     * difference is increased to the input as a hook fee. Note that the fee is always applied to the unspecified
     * currency of the swap, regardless of the swap direction.
     *
     * The fees are minted to this hook as ERC-6909 tokens, which can then be distribuited in {_afterSwapHandler}
     *
     * NOTE: The target unspecified amount and the apply flag are reset on purpose to avoid state overlapping across swaps.
     */
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) internal virtual override returns (bytes4, int128) {
        // Cache the target unspecified amount in memory
        uint256 targetUnspecifiedAmount = _transientTargetUnspecifiedAmount();

        // Reset the transiently stored target unspecified amount to 0, use the cached value in memory.
        _setTransientTargetUnspecifiedAmount(0);

        // Skip if the target unspecified amount should not be applied
        if (!_transientApplyTarget()) {
            return (this.afterSwap.selector, 0);
        }

        // Reset the stored apply flag
        _setTransientApplyTarget(false);

        // Fee defined in the unspecified currency of the swap
        (Currency unspecified, int128 unspecifiedAmount) = (params.amountSpecified < 0 == params.zeroForOne)
            ? (key.currency1, delta.amount1())
            : (key.currency0, delta.amount0());

        // Get the absolute unspecified amount
        if (unspecifiedAmount < 0) unspecifiedAmount = -unspecifiedAmount;

        // Get the exact input flag
        bool exactInput = params.amountSpecified < 0;

        uint256 feeAmount;

        // If the swap is exactInput, any fee should be decreased from the swap output
        if (exactInput) {
            // If the swap output exceeds the target, decrease it by the difference as a hook fee
            if (unspecifiedAmount.toUint256() > targetUnspecifiedAmount) {
                feeAmount = unspecifiedAmount.toUint256() - targetUnspecifiedAmount;
            }
            // If the swap output is less or equal than the target, behave as a no-op
        }
        // If the swap is exactOutput, any fee should be increased to the swap input
        else {
            // If the swap input is less than the target, increase it by the difference as a hook fee
            if (unspecifiedAmount.toUint256() < targetUnspecifiedAmount) {
                feeAmount = targetUnspecifiedAmount - unspecifiedAmount.toUint256();
            }
            // If the swap input is greater or equal than the target, behave as a no-op
        }

        if (feeAmount > 0) {
            // Mint ERC-6909 tokens for unspecified currency fee and call handler
            unspecified.take(poolManager, address(this), feeAmount.toUint128(), true);
            _afterSwapHandler(key, params, delta, targetUnspecifiedAmount, feeAmount);

            // Emit the swap event with the amounts ordered correctly
            if (unspecified == key.currency0) {
                emit HookFee(PoolId.unwrap(key.toId()), sender, feeAmount.toUint128(), 0);
            } else {
                emit HookFee(PoolId.unwrap(key.toId()), sender, 0, feeAmount.toUint128());
            }
        }

        return (this.afterSwap.selector, feeAmount.toInt256().toInt128());
    }

    /**
     * @dev Return the target unspecified amount to be enforced by the `afterSwap` hook.
     *
     * @return targetUnspecifiedAmount The target unspecified amount, defined in the unspecified currency of the swap.
     * @return applyTarget The apply flag, which can be set to `false` to skip applying the target output.
     */
    function _getTargetUnspecified(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) internal virtual returns (uint256 targetUnspecifiedAmount, bool applyTarget);

    /**
     * @dev Customizable handler called after `_afterSwap` to handle or distribuite the fees.
     *
     * @param key The pool key.
     * @param params The swap parameters.
     * @param delta The balance delta.
     * @param targetUnspecifiedAmount The target unspecified amount.
     * @param feeAmount The fee amount.
     *
     * WARNING: If the underlying unspecified currency is native, the implementing contract must ensure that it can
     * receive and handle it when redeeming.
     */
    function _afterSwapHandler(
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        uint256 targetUnspecifiedAmount,
        uint256 feeAmount
    ) internal virtual;

    /**
     * @dev Set the hook permissions, specifically {beforeSwap}, {afterSwap} and {afterSwapReturnDelta}.
     *
     * @return permissions The hook permissions.
     */
    function getHookPermissions() public pure virtual override returns (Hooks.Permissions memory permissions) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
}
