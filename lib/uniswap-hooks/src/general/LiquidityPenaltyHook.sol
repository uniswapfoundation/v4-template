// SPDX-License-Identifier: MIT
// OpenZeppelin Uniswap Hooks (last updated v1.1.0) (src/general/LiquidityPenaltyHook.sol)

pragma solidity ^0.8.24;

// Internal imports
import {BaseHook} from "../base/BaseHook.sol";
import {CurrencySettler} from "../utils/CurrencySettler.sol";

// External imports
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Position} from "v4-core/src/libraries/Position.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";

/**
 * @dev Just-in-Time (JIT) liquidity provisioning resistant hook.
 *
 * This hook disincentivizes JIT attacks by penalizing LP fee collection during {_afterRemoveLiquidity},
 * and disabling it during {_afterAddLiquidity} if liquidity was recently added to the position.
 * The penalty is donated to the pool's liquidity providers in range at the time of removal.
 *
 * See {_calculateLiquidityPenalty} for penalty calculation.
 *
 * NOTE: If a long term liquidity provider adds liquidity continuously, a pause of `blockNumberOffset`
 * before removing will be needed if `feesAccrued` collection is intended, in order to avoid getting
 * penalized by the JIT protection mechanism.
 *
 * WARNING: Altrough this hook achieves it's objective of protecting long term LP's in most scenarios,
 * low liquidity pools and long-tail assets may still be vulnerable depending on the configured `blockNumberOffset`.
 * Larger values of such are recommended in those cases in order to decrease the profitability of the attack.
 *
 * WARNING: In low liquidity pools, this hook may be vulnerable to multi-account strategies: attackers may bypass JIT protection
 * by using a secondary account to add minimal liquidity at a target tick with no other liquidity, then moving the price there after a JIT attack.
 * This allows penalty fees to be redirected to the attacker's secondary account. While technically feasible, this attack is rarely profitable in practice,
 * due to the cost associated with moving the price to the target tick.
 *
 * WARNING: This is experimental software and is provided on an "as is" and "as available" basis. We do
 * not give any warranties and will not be liable for any losses incurred through any use of this code
 * base.
 *
 * _Available since v0.1.1_
 */
contract LiquidityPenaltyHook is BaseHook {
    using CurrencySettler for Currency;
    using StateLibrary for IPoolManager;
    using SafeCast for uint256;

    /**
     * @dev The hook was attempted to be constructed with a `blockNumberOffset` lower than `MIN_BLOCK_NUMBER_OFFSET`.
     */
    error BlockNumberOffsetTooLow();

    /**
     * @dev A penalty was attempted to be applied and donated to LP's in range, but there aren't any.
     */
    error NoLiquidityToReceiveDonation();

    /**
     * @dev The minimum block number offset.
     */
    uint48 public constant MIN_BLOCK_NUMBER_OFFSET = 1;

    /**
     * @dev The block number offset.
     */
    uint48 private immutable _blockNumberOffset;

    /**
     * @dev Tracks the `lastAddedLiquidityBlock` for a liquidity position.
     */
    mapping(PoolId poolId => mapping(bytes32 positionKey => uint48 blockNumber)) private _lastAddedLiquidityBlock;

    /**
     * @dev Tracks the `withheldFees` for a liquidity position.
     */
    mapping(PoolId poolId => mapping(bytes32 positionKey => BalanceDelta delta)) private _withheldFees;

    /**
     * @dev Sets the `PoolManager` address and the {getBlockNumberOffset}.
     */
    constructor(IPoolManager poolManager_, uint48 blockNumberOffset_) BaseHook(poolManager_) {
        if (blockNumberOffset_ < MIN_BLOCK_NUMBER_OFFSET) revert BlockNumberOffsetTooLow();
        _blockNumberOffset = blockNumberOffset_;
    }

    /**
     * @dev Tracks `lastAddedLiquidityBlock` and withholds `feeDelta` if liquidity was recently added within
     * the `blockNumberOffset` period.
     *
     * See {_afterRemoveLiquidity} for claiming the withheld fees back.
     */
    function _afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta, /* delta */
        BalanceDelta feeDelta,
        bytes calldata
    ) internal virtual override returns (bytes4, BalanceDelta) {
        PoolId poolId = key.toId();
        bytes32 positionKey = Position.calculatePositionKey(sender, params.tickLower, params.tickUpper, params.salt);

        // If liquidity was added recently within the `blockNumberOffset`, retain the feeDelta in this hook.
        if (_getBlockNumber() - getLastAddedLiquidityBlock(poolId, positionKey) < getBlockNumberOffset()) {
            _updateLastAddedLiquidityBlock(poolId, positionKey);
            _takeFeesToHook(key, positionKey, feeDelta);

            return (this.afterAddLiquidity.selector, feeDelta);
        }

        _updateLastAddedLiquidityBlock(poolId, positionKey);

        return (this.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    /**
     * @dev Penalizes the collection of any existing LP `feesDelta` and `withheldFees` after liquidity removal if
     * liquidity was recently added to the position.
     *
     * NOTE: The penalty is applied on both `withheldFees` and `feeDelta` equally.
     * Therefore, regardless of how many times liquidity was added to the position within the `blockNumberOffset` period,
     * all accrued fees are penalized as if the liquidity was added only once during that period. This ensures that
     * splitting liquidity additions within the `blockNumberOffset` period does not reduce or increase the penalty.
     *
     * IMPORTANT: The penalty is donated to the pool's liquidity providers in range at the time of liquidity removal,
     * which may be different from the liquidity providers in range at the time of liquidity addition.
     */
    function _afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta, /* delta */
        BalanceDelta feeDelta,
        bytes calldata
    ) internal virtual override returns (bytes4, BalanceDelta) {
        PoolId poolId = key.toId();
        bytes32 positionKey = Position.calculatePositionKey(sender, params.tickLower, params.tickUpper, params.salt);

        // Receive back the `withheldFees` retained during previous liquidity additions within the `blockNumberOffset`.
        BalanceDelta withheldFees = _settleFeesFromHook(key, positionKey);

        // The total fees accrued by the LP are the sum of the `feeDelta` plus the `withheldFees`.
        BalanceDelta totalFees = feeDelta + withheldFees;

        // cache lastAddedLiquidity in memory
        uint48 lastAddedLiquidityBlock = getLastAddedLiquidityBlock(poolId, positionKey);

        if (
            _getBlockNumber() - lastAddedLiquidityBlock < getBlockNumberOffset()
                && totalFees != BalanceDeltaLibrary.ZERO_DELTA
        ) {
            BalanceDelta liquidityPenalty = _calculateLiquidityPenalty(totalFees, lastAddedLiquidityBlock);

            // If there is a penalty to be applied but there are no active liquidity positions in range to
            // receive the donation, then the liquidity removal is not possible and the offset must be awaited.
            if (poolManager.getLiquidity(poolId) == 0) revert NoLiquidityToReceiveDonation();

            poolManager.donate(
                key, uint256(int256(liquidityPenalty.amount0())), uint256(int256(liquidityPenalty.amount1())), ""
            );

            return (this.afterRemoveLiquidity.selector, liquidityPenalty - withheldFees);
        }

        // If the liquidity removal was not penalized, return the withheld fees if any.
        if (withheldFees != BalanceDeltaLibrary.ZERO_DELTA) {
            BalanceDelta returnDelta = toBalanceDelta(-withheldFees.amount0(), -withheldFees.amount1());
            return (this.afterRemoveLiquidity.selector, returnDelta);
        }

        return (this.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    /**
     * @dev Returns the current block number.
     */
    function _getBlockNumber() internal view virtual returns (uint48) {
        return uint48(block.number);
    }

    /**
     * @dev Updates the `lastAddedLiquidityBlock` for a liquidity position.
     */
    function _updateLastAddedLiquidityBlock(PoolId poolId, bytes32 positionKey) internal virtual {
        _lastAddedLiquidityBlock[poolId][positionKey] = _getBlockNumber();
    }

    /**
     * @dev Takes `feeDelta` from a liquidity position as `withheldFees` into this hook.
     */
    function _takeFeesToHook(PoolKey calldata key, bytes32 positionKey, BalanceDelta feeDelta) internal virtual {
        PoolId poolId = key.toId();

        _withheldFees[poolId][positionKey] = _withheldFees[poolId][positionKey] + feeDelta;

        key.currency0.take(poolManager, address(this), uint256(uint128(feeDelta.amount0())), true);
        key.currency1.take(poolManager, address(this), uint256(uint128(feeDelta.amount1())), true);
    }

    /**
     * @dev Returns `withheldFees` from this hook to the liquidity provider.
     */
    function _settleFeesFromHook(PoolKey calldata key, bytes32 positionKey)
        internal
        virtual
        returns (BalanceDelta withheldFees)
    {
        PoolId poolId = key.toId();

        withheldFees = getWithheldFees(poolId, positionKey);

        // Reset the `withheldFees`.
        _withheldFees[poolId][positionKey] = BalanceDeltaLibrary.ZERO_DELTA;

        // Settle the `withheldFees` for the liquidity position.
        if (withheldFees.amount0() > 0) {
            key.currency0.settle(poolManager, address(this), uint256(uint128(withheldFees.amount0())), true);
        }
        if (withheldFees.amount1() > 0) {
            key.currency1.settle(poolManager, address(this), uint256(uint128(withheldFees.amount1())), true);
        }
    }

    /**
     * @dev Calculates the penalty to be applied to JIT liquidity provisioning.
     *
     * The penalty is calculated as a linear function of the block number difference between the `lastAddedLiquidityBlock` and the `currentBlockNumber`.
     *
     * The used formula is:
     *
     * liquidityPenalty = feeDelta * ( 1 - (currentBlockNumber - lastAddedLiquidityBlock) / blockNumberOffset)
     *
     * As a result, the penalty is 100% at the same block where liquidity was last added and zero after the `blockNumberOffset` block time window.
     *
     * NOTE: Won't overflow if `currentBlockNumber - lastAddedLiquidityBlock < blockNumberOffset` is verified prior to calling this function.
     */
    function _calculateLiquidityPenalty(BalanceDelta feeDelta, uint48 lastAddedLiquidityBlock)
        internal
        virtual
        returns (BalanceDelta liquidityPenalty)
    {
        uint48 currentBlockNumber = _getBlockNumber();
        uint48 blockNumberOffset = getBlockNumberOffset();

        unchecked {
            uint256 amount0LiquidityPenalty = FullMath.mulDiv(
                SafeCast.toUint128(feeDelta.amount0()),
                blockNumberOffset - (currentBlockNumber - lastAddedLiquidityBlock), // won't overflow.
                blockNumberOffset
            );
            uint256 amount1LiquidityPenalty = FullMath.mulDiv(
                SafeCast.toUint128(feeDelta.amount1()),
                blockNumberOffset - (currentBlockNumber - lastAddedLiquidityBlock), // won't overflow.
                blockNumberOffset
            );

            // Although the amounts are returned as uint256, they must fit in int128, since they are fee rewards.
            liquidityPenalty = toBalanceDelta(amount0LiquidityPenalty.toInt128(), amount1LiquidityPenalty.toInt128());
        }
    }

    /**
     * @dev The minimum time window (in blocks) that must pass after adding liquidity before it can be
     * removed without any penalty. During this period, JIT attacks are deterred through fee withholding
     * and penalties. Higher values provide stronger JIT protection but may discourage legitimate LPs.
     */
    function getBlockNumberOffset() public view virtual returns (uint48) {
        return _blockNumberOffset;
    }

    /**
     * @dev Tracks the `lastAddedLiquidityBlock` for a liquidity position.
     *
     * `lastAddedLiquidityBlock` is the block number when liquidity was last added to the position.
     */
    function getLastAddedLiquidityBlock(PoolId poolId, bytes32 positionKey) public view virtual returns (uint48) {
        return _lastAddedLiquidityBlock[poolId][positionKey];
    }

    /**
     * @dev Returns the `withheldFees` for a liquidity position.
     *
     * `withheldFees` are UniswapV4's `feesAccrued` retained by this hook during liquidity addition if liquidity
     * has been recently added within the `blockNumberOffset` block time window, with the purpose of disabling fee
     * collection during JIT liquidity provisioning attacks. See {_afterRemoveLiquidity} for claiming the fees back.
     */
    function getWithheldFees(PoolId poolId, bytes32 positionKey) public view virtual returns (BalanceDelta) {
        return _withheldFees[poolId][positionKey];
    }

    /**
     * @dev Set the hooks permissions, specifically `afterAddLiquidity`, `afterAddLiquidityReturnDelta`, `afterRemoveLiquidity` and `afterRemoveLiquidityReturnDelta`.
     */
    function getHookPermissions() public pure virtual override returns (Hooks.Permissions memory permissions) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: true,
            beforeSwap: false,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: true,
            afterRemoveLiquidityReturnDelta: true
        });
    }
}
