// SPDX-License-Identifier: MIT
// OpenZeppelin Uniswap Hooks (last updated v1.1.0) (src/general/AntiSandwichHook.sol)

pragma solidity ^0.8.24;

// Internal imports
import {BaseDynamicAfterFee} from "../fee/BaseDynamicAfterFee.sol";
import {CurrencySettler} from "../utils/CurrencySettler.sol";

// External imports
import {Pool} from "v4-core/src/libraries/Pool.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Slot0} from "v4-core/src/types/Slot0.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";

/**
 * @dev This hook implements the sandwich-resistant AMM design introduced
 * https://www.umbraresearch.xyz/writings/sandwich-resistant-amm[here]. Specifically,
 * this hook guarantees that no swaps get filled at a price better than the price at
 * the beginning of the slot window (i.e. one block).
 *
 * Within a slot window, swaps impact the pool asymmetrically for buys and sells.
 * When a buy order is executed, the offer on the pool increases in accordance with
 * the xy=k curve. However, the bid price remains constant, instead increasing the
 * amount of liquidity on the bid. Subsequent sells eat into this liquidity, while
 * decreasing the offer price according to xy=k.
 *
 * In order to use this hook, the inheriting contract must implement the {_handleCollectedFees} function
 * to determine how to handle the collected fees from the anti-sandwich mechanism.
 *
 * NOTE: The Anti-sandwich mechanism only protects swaps in the zeroForOne swap direction.
 * Swaps in the !zeroForOne direction are not protected by this hook design.
 *
 * WARNING: Since this hook makes MEV not profitable, there's not as much arbitrage in
 * the pool, making prices at beginning of the block not necessarily close to market price.
 *
 * WARNING: In `_beforeSwap`, the hook iterates over all ticks between last tick and current tick.
 * Developers must be aware that for large price changes in pools with small tick spacing, the `for`
 * loop will iterate over a large number of ticks, which could lead to `MemoryOOG` error.
 *
 * WARNING: This is experimental software and is provided on an "as is" and "as available" basis. We do
 * not give any warranties and will not be liable for any losses incurred through any use of this code
 * base.
 *
 * _Available since v1.1.0_
 */
abstract contract AntiSandwichHook is BaseDynamicAfterFee {
    using Pool for *;
    using StateLibrary for IPoolManager;
    using CurrencySettler for Currency;
    using SafeCast for *;

    /// @dev Represents a checkpoint of the pool state at the beginning of a block.
    struct Checkpoint {
        uint48 blockNumber;
        Pool.State state;
    }

    /// @dev Maps each pool to its last checkpoint.
    mapping(PoolId id => Checkpoint) private _lastCheckpoints;

    constructor(IPoolManager _poolManager) BaseDynamicAfterFee(_poolManager) {}

    /**
     * @dev Handles the before swap hook.
     *
     * For the first swap in a block, it saves the current pool state as a checkpoint.
     *
     * For subsequent swaps in the same block, it calculates a target output based on the beginning-of-block state,
     * and sets the inherited `_targetOutput` and `_applyTargetOutput` variables to enforce price limits in {_afterSwap}.
     */
    function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        internal
        virtual
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolId poolId = key.toId();
        Checkpoint storage _lastCheckpoint = _lastCheckpoints[poolId];

        uint48 currentBlock = _getBlockNumber();

        // update the top-of-block `slot0` if new block
        if (_lastCheckpoint.blockNumber != currentBlock) {
            int24 lastTick = _lastCheckpoint.state.slot0.tick();
            _lastCheckpoint.state.slot0 = Slot0.wrap(poolManager.extsload(StateLibrary._getPoolStateSlot(poolId)));
            _lastCheckpoint.blockNumber = currentBlock;

            // iterate over ticks
            (, int24 currentTick,,) = poolManager.getSlot0(poolId);
            if (currentTick < lastTick) {
                for (int24 tick = currentTick; tick <= lastTick; tick += key.tickSpacing) {
                    (
                        _lastCheckpoint.state.ticks[tick].liquidityGross,
                        _lastCheckpoint.state.ticks[tick].liquidityNet,
                        _lastCheckpoint.state.ticks[tick].feeGrowthOutside0X128,
                        _lastCheckpoint.state.ticks[tick].feeGrowthOutside1X128
                    ) = poolManager.getTickInfo(poolId, tick);
                }
            } else {
                for (int24 tick = currentTick; tick >= lastTick; tick -= key.tickSpacing) {
                    (
                        _lastCheckpoint.state.ticks[tick].liquidityGross,
                        _lastCheckpoint.state.ticks[tick].liquidityNet,
                        _lastCheckpoint.state.ticks[tick].feeGrowthOutside0X128,
                        _lastCheckpoint.state.ticks[tick].feeGrowthOutside1X128
                    ) = poolManager.getTickInfo(poolId, tick);
                }
            }

            (_lastCheckpoint.state.feeGrowthGlobal0X128, _lastCheckpoint.state.feeGrowthGlobal1X128) =
                poolManager.getFeeGrowthGlobals(poolId);
            _lastCheckpoint.state.liquidity = poolManager.getLiquidity(poolId);
        }

        return super._beforeSwap(sender, key, params, hookData);
    }

    /**
     * @dev Returns the current block number.
     */
    function _getBlockNumber() internal view virtual returns (uint48) {
        return uint48(block.number);
    }

    /**
     * @dev Calculates the unspecified amount based on the pool state at the beginning of the block.
     * This prevents sandwich attacks by ensuring trades can't get better prices than what was available
     * at the start of the block. Note that the calculated unspecified amount could either be input or output, depending
     * if it's an exactInput or outputOutput swap. In cases of zeroForOne == true, the target unspecified amount is not
     * applicable, and the max uint256 value is returned as a flag only.
     *
     * The anti-sandwich mechanism works such as:
     *
     * - For currency0 to currency1 swaps (zeroForOne = true): The pool behaves normally with xy=k curve.
     * - For currency1 to currency0 swaps (zeroForOne = false): The price is fixed at the beginning-of-block
     *   price, which prevents attackers from manipulating the price within a block.
     */
    function _getTargetUnspecified(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal
        virtual
        override
        returns (uint256 targetUnspecifiedAmount, bool applyTarget)
    {
        if (params.zeroForOne) {
            // when zeroForOne == true, the xy=k curve is used, so the target output doesn't matter, since it's not going to be used
            // we return the max value to indicate that the target output is not applicable
            return (type(uint256).max, false);
        }

        Checkpoint storage _lastCheckpoint = _lastCheckpoints[key.toId()];

        // Simulate the swap to get the swap delta
        // NOTE: this functions does not execute the swap, it only calculates the output of a swap in the given state
        (BalanceDelta swapDelta,,,) = Pool.swap(
            _lastCheckpoint.state,
            Pool.SwapParams({
                tickSpacing: key.tickSpacing,
                zeroForOne: params.zeroForOne,
                amountSpecified: params.amountSpecified,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96,
                lpFeeOverride: 0
            })
        );

        // Get the unspecified amount from the swap delta
        int128 target = (params.amountSpecified < 0 == params.zeroForOne) ? swapDelta.amount1() : swapDelta.amount0();

        // Get the absolute unspecified amount
        if (target < 0) target = -target;

        targetUnspecifiedAmount = target.toUint256();
        applyTarget = true;
    }

    /**
     * @dev Set the hook permissions, specifically `beforeSwap`, `afterSwap`, and `afterSwapReturnDelta`.
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
