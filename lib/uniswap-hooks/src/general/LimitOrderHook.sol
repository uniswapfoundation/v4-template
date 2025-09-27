// SPDX-License-Identifier: MIT
// OpenZeppelin Uniswap Hooks (last updated v1.1.0) (src/general/LimitOrderHook.sol)

pragma solidity ^0.8.24;

// Internal imports
import {CurrencySettler} from "../utils/CurrencySettler.sol";
import {BaseHook} from "../base/BaseHook.sol";

// External imports
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";

/// @dev The order id library.
library OrderIdLibrary {
    /// @dev The order id type.
    type OrderId is uint232;

    /**
     * @dev Compare two order ids for equality. Takes two `OrderId` values `a` and `b` and
     * returns whether their underlying values are equal.
     */
    function equals(OrderId a, OrderId b) internal pure returns (bool) {
        return OrderId.unwrap(a) == OrderId.unwrap(b);
    }

    /// @dev Increment the order id `a`. Might overflow.
    function unsafeIncrement(OrderId a) internal pure returns (OrderId) {
        unchecked {
            return OrderId.wrap(OrderId.unwrap(a) + 1);
        }
    }
}

/**
 * @dev Limit Order Mechanism hook.
 *
 * Allows users to place limit orders at specific ticks outside of the current price range,
 * which will be filled if the pool's price crosses the order's tick.
 *
 * Note that given the way UniswapV4 pools works, when liquidity is added out of the current range,
 * a single currency will be provided, instead of both currencies as in in-range liquidity additions.
 *
 * Orders can be cancelled at any time until they are filled and their liquidity is removed from the pool.
 * Once completely filled, the resulting liquidity can be withdrawn from the pool.
 *
 * IMPORTANT: When cancelling or adding more liquidity into an existing order, it's possible that fees
 * have been accrued. In those cases, the accrued fees are added to the order info, benefitting the remaining
 * limit order placers.
 *
 * WARNING: This is experimental software and is provided on an "as is" and "as available" basis. We do
 * not give any warranties and will not be liable for any losses incurred through any use of this code
 * base.
 *
 * _Available since v1.1.0_
 */
contract LimitOrderHook is BaseHook, IUnlockCallback {
    using StateLibrary for IPoolManager;
    using OrderIdLibrary for OrderIdLibrary.OrderId;
    using CurrencySettler for Currency;

    /// @dev The info for each order id.
    struct OrderInfo {
        bool filled;
        Currency currency0;
        Currency currency1;
        uint256 currency0Total;
        uint256 currency1Total;
        uint128 liquidityTotal;
        mapping(address owner => uint128 amount) liquidity;
        mapping(address owner => CheckpointCurrencies checkpoint) checkpoints;
    }

    /// @dev Types of callbacks performed by the poolManager in `{unlockCallback}`
    enum CallbackType {
        Place,
        Cancel,
        Withdraw
    }

    /// @dev Struct of callback data passed by the poolManager in `{unlockCallback}`.
    struct CallbackData {
        CallbackType callbackType;
        bytes data;
    }

    /// @dev Struct of callback data for the place callback.
    struct PlaceCallbackData {
        PoolKey key;
        address owner;
        bool zeroForOne;
        int24 tickLower;
        uint128 liquidity;
    }

    /// @dev Struct of callback data for the cancel callback.
    struct CancelCallbackData {
        PoolKey key;
        int24 tickLower;
        int256 liquidityDelta;
        address to;
        bool removingAllLiquidity;
    }

    /// @dev Struct of callback data for the withdraw callback
    struct WithdrawCallbackData {
        Currency currency0;
        Currency currency1;
        uint256 currency0Amount;
        uint256 currency1Amount;
        address to;
    }

    /**
     * @dev Struct of checkpoint currencies. These are the amounts of `currency0` and `currency1` marked
     * as `currency0Total` and `currency1Total` in the `OrderInfo` struct at the time of the checkpoint.
     */
    struct CheckpointCurrencies {
        uint256 amountCurrency0;
        uint256 amountCurrency1;
    }

    /// @dev The zero bytes.
    bytes internal constant ZERO_BYTES = bytes("");

    /// @dev The default order id, used to indicate that an order is not yet initialized.
    OrderIdLibrary.OrderId private constant ORDER_ID_DEFAULT = OrderIdLibrary.OrderId.wrap(0);

    /// @dev The next order id to be used.
    OrderIdLibrary.OrderId private orderIdNext = OrderIdLibrary.OrderId.wrap(1);

    /// @dev The last tick lower for each pool.
    mapping(PoolId poolId => int24 tickLowerLast) private tickLowerLasts;

    /// @dev Tracks each order id for a given identifier, defined by keccak256 of the key, tick lower, and zero for one.
    mapping(bytes32 orderKey => OrderIdLibrary.OrderId orderId) private orders;

    /// @dev Tracks the order info for each order id.
    mapping(OrderIdLibrary.OrderId orderId => OrderInfo orderInfo) public orderInfos;

    /// @dev Zero liquidity was attempted to be added or removed.
    error ZeroLiquidity();

    /// @dev Limit order was placed in range.
    error InRange();

    /// @dev Limit order placed on the wrong side of the range.
    error CrossedRange();

    /// @dev Limit order was already filled.
    error Filled();

    /// @dev Limit order is not filled.
    error NotFilled();

    /**
     * @dev Emitted when an `owner` places a limit order with the given `orderId`, in the pool identified by `key`,
     * at the given `tickLower`, `zeroForOne` indicating the direction of the order, and `liquidity` the amount of liquidity
     * added.
     */
    event Place(
        address indexed owner,
        OrderIdLibrary.OrderId indexed orderId,
        PoolKey key,
        int24 tickLower,
        bool zeroForOne,
        uint128 liquidity
    );

    /**
     * @dev Emitted when a limit order with the given `orderId` is filled in the pool identified by `key`,
     * at the given `tickLower`, `zeroForOne` indicating the direction of the order.
     */
    event Fill(OrderIdLibrary.OrderId indexed orderId, PoolKey key, int24 tickLower, bool zeroForOne);

    /**
     * @dev Emitted when an `owner` cancels a limit order with the given `orderId`, in the pool identified by `key`,
     * at the given `tickLower`, `zeroForOne` indicating the direction of the order, and `liquidity` the amount of liquidity
     * removed.
     */
    event Cancel(
        address indexed owner,
        OrderIdLibrary.OrderId indexed orderId,
        PoolKey key,
        int24 tickLower,
        bool zeroForOne,
        uint128 liquidity
    );

    /**
     * @dev Emitted when an `owner` withdraws their `liquidity` from a limit order with the given `orderId`, in the pool identified by `key`,
     * at the given `tickLower`, `zeroForOne` indicating the direction of the order.
     */
    event Withdraw(address indexed owner, OrderIdLibrary.OrderId indexed orderId, uint128 liquidity);

    /// @dev Set the `PoolManager` address.
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    /// @dev Hooks into the `afterInitialize` hook to set the last tick lower for the pool.
    function _afterInitialize(address, PoolKey calldata key, uint160, int24 tick) internal override returns (bytes4) {
        // set the last tick lower for the pool
        tickLowerLasts[key.toId()] = getTickLower(tick, key.tickSpacing);

        return this.afterInitialize.selector;
    }

    /// @dev Hooks into the `afterSwap` hook to get the ticks crossed by the swap and fill the orders that are crossed, filling them.
    function _afterSwap(address, PoolKey calldata key, SwapParams calldata params, BalanceDelta, bytes calldata)
        internal
        virtual
        override
        returns (bytes4, int128)
    {
        (int24 tickLower, int24 lower, int24 upper) = _getCrossedTicks(key.toId(), key.tickSpacing);

        if (lower > upper) return (this.afterSwap.selector, 0);

        // set the last tick lower for the pool
        tickLowerLasts[key.toId()] = tickLower;

        // note that a zeroForOne swap means that the pool is actually gaining token0, so limit
        // order fills are the opposite of swap fills, hence the inversion below
        bool zeroForOne = !params.zeroForOne;
        for (; lower <= upper; lower += key.tickSpacing) {
            _fillOrder(key, lower, zeroForOne);
        }

        return (this.afterSwap.selector, 0);
    }

    /**
     * @dev Places a limit order by adding liquidity out of range at a specific tick. The order will be filled when the
     * pool price crosses the specified `tick`. Takes a `PoolKey` `key`, target `tick`, direction `zeroForOne` indicating
     * whether to buy currency0 or currency1, and amount of `liquidity` to place. The interaction with the `poolManager` is done
     * via the `unlock` function, which will trigger the `{unlockCallback}` function.
     */
    function placeOrder(PoolKey calldata key, int24 tick, bool zeroForOne, uint128 liquidity) external {
        if (liquidity == 0) revert ZeroLiquidity();

        OrderInfo storage orderInfo;

        // get the order for the limit order
        OrderIdLibrary.OrderId orderId = getOrderId(key, tick, zeroForOne);

        // if the order is not initialized, initialize it
        if (orderId.equals(ORDER_ID_DEFAULT)) {
            // initialize the order to the next order
            unchecked {
                setOrderId(key, tick, zeroForOne, orderId = orderIdNext);

                // increment the order id
                orderIdNext = orderIdNext.unsafeIncrement();
            }

            // get the order info
            orderInfo = orderInfos[orderId];

            // set the currency0 and currency1
            orderInfo.currency0 = key.currency0;
            orderInfo.currency1 = key.currency1;
        } else {
            // get the order info
            orderInfo = orderInfos[orderId];
        }

        // add the liquidity to the order
        unchecked {
            orderInfo.liquidityTotal += liquidity;
            orderInfo.liquidity[msg.sender] += liquidity;
        }
        // set the currency checkpoints for the msg.sender. These amounts are stored so that the user cannot steal
        // fees accrued before the checkpoint. Note that the amounts in the checkpoints can only be from fees accrued,
        // never from order fills. The checkpoint is updated every time the user places an order.
        // This means possible fees accrued in between checkpoints are not taken into account, so the user is not entitled to them.
        orderInfo.checkpoints[msg.sender].amountCurrency0 = orderInfo.currency0Total;
        orderInfo.checkpoints[msg.sender].amountCurrency1 = orderInfo.currency1Total;

        // unlock the callback to the poolManager, the callback will trigger `unlockCallback`
        // note that multiple functions trigger `unlockCallback`, so the `callbackData.callbackType` will determine what happens
        // in `unlockCallback`. In this case, it will add liquidity out of range.
        // IMPORTANT: `tick` must be valid, i.e. within the range of `MIN_TICK` and `MAX_TICK`, defined in the `TickMath` library and it must be
        // a multiple of `key.tickSpacing`.
        (uint256 amount0Fee, uint256 amount1Fee) = abi.decode(
            poolManager.unlock(
                abi.encode(
                    CallbackData(
                        CallbackType.Place, abi.encode(PlaceCallbackData(key, msg.sender, zeroForOne, tick, liquidity))
                    )
                )
            ),
            (uint256, uint256)
        );

        // add the fees to the order info
        // note that the currency totals must be updated after poolManager call as they depend on the returned values of the callback.
        // This is safe as these functions are only callable on the trusted poolManager
        unchecked {
            // slither-disable-next-line reentrancy-no-eth
            orderInfo.currency0Total += amount0Fee;
            // slither-disable-next-line reentrancy-no-eth
            orderInfo.currency1Total += amount1Fee;
        }

        // emit the place event
        emit Place(msg.sender, orderId, key, tick, zeroForOne, liquidity);
    }

    /**
     * @dev Cancels a limit order by removing liquidity from the pool. Takes a `PoolKey` `key`, `tickLower` of the order,
     * direction `zeroForOne` indicating whether it was buying currency0 or currency1, and recipient address `to` for the
     * removed liquidity. Note that partial cancellation is not supported - the entire liquidity added by the msg.sender will be removed.
     * Note also that cancelling an order will cancel the order placed by the msg.sender, not orders placed by other users in the same tick range.
     * The interaction with the `poolManager` is done via the `unlock` function, which will trigger the `{unlockCallback}` function.
     */
    function cancelOrder(PoolKey calldata key, int24 tickLower, bool zeroForOne, address to) external {
        // get the order
        OrderIdLibrary.OrderId orderId = getOrderId(key, tickLower, zeroForOne);
        OrderInfo storage orderInfo = orderInfos[orderId];

        // revert if the order is already filled
        if (orderInfo.filled) revert Filled();

        // get the liquidity added by the msg.sender
        uint128 liquidity = orderInfo.liquidity[msg.sender];

        // revert if the liquidity is 0
        if (liquidity == 0) revert ZeroLiquidity();

        // delete the liquidity from the order
        delete orderInfo.liquidity[msg.sender];

        bool removingAllLiquidity = liquidity == orderInfo.liquidityTotal;
        // subtract the liquidity from the total liquidity
        orderInfo.liquidityTotal -= liquidity;

        if (removingAllLiquidity) {
            setOrderId(key, tickLower, zeroForOne, ORDER_ID_DEFAULT);
            orderInfo.currency0Total = 0;
            orderInfo.currency1Total = 0;
        }

        // unlock the callback to the poolManager, the callback will trigger `unlockCallback`
        // and remove the liquidity from the pool. Note that this function will return the fees accrued
        // by the position, since the limit order is a liquidity addition.
        // Note that `amount0Fee` and `amount1Fee` are the fees accrued by the position and will not be transferred to
        // the `to` address. Instead, they will be added to the order info (benefiting the remaining limit order placers).
        (uint256 amount0Fee, uint256 amount1Fee) = abi.decode(
            poolManager.unlock(
                abi.encode(
                    CallbackData(
                        CallbackType.Cancel,
                        abi.encode(
                            CancelCallbackData(key, tickLower, -int256(uint256(liquidity)), to, removingAllLiquidity)
                        )
                    )
                )
            ),
            (uint256, uint256)
        );

        // add the fees to the order info
        // note that the currency totals must be updated after poolManager call as they depend on the returned values of the callback.
        // This is safe as these functions are only callable on the trusted poolManager
        unchecked {
            // slither-disable-next-line reentrancy-no-eth
            orderInfo.currency0Total += amount0Fee;
            // slither-disable-next-line reentrancy-no-eth
            orderInfo.currency1Total += amount1Fee;
        }

        // emit the cancel event
        emit Cancel(msg.sender, orderId, key, tickLower, zeroForOne, liquidity);
    }

    /**
     * @dev Withdraws liquidity from a filled order, sending it to address `to`. Takes an `OrderId` `orderId` of the filled
     * order to withdraw from. Returns the withdrawn amounts as `(amount0, amount1)`. Can only be called after the order is
     * filled - use `cancelOrder` to remove liquidity from unfilled orders. The interaction with the `poolManager` is done via the
     * `unlock` function, which will trigger the `{unlockCallback}` function.
     */
    function withdraw(OrderIdLibrary.OrderId orderId, address to) external returns (uint256 amount0, uint256 amount1) {
        // get the order info
        OrderInfo storage orderInfo = orderInfos[orderId];

        // revert if the order is not filled
        if (!orderInfo.filled) revert NotFilled();

        // get the liquidity added by the msg.sender
        uint128 liquidity = orderInfo.liquidity[msg.sender];

        // revert if the liquidity is 0
        if (liquidity == 0) revert ZeroLiquidity();

        // delete the liquidity from the order
        delete orderInfo.liquidity[msg.sender];

        // get the total liquidity in the order
        uint128 liquidityTotal = orderInfo.liquidityTotal;

        uint256 checkpointAmountCurrency0 = orderInfo.checkpoints[msg.sender].amountCurrency0;
        uint256 checkpointAmountCurrency1 = orderInfo.checkpoints[msg.sender].amountCurrency1;

        // calculate the amount of currency0 and currency1 owed to the msg.sender
        // note that the user is not able to withdraw funds that were accrued before their checkpoint.
        amount0 = FullMath.mulDiv(orderInfo.currency0Total - checkpointAmountCurrency0, liquidity, liquidityTotal);
        amount1 = FullMath.mulDiv(orderInfo.currency1Total - checkpointAmountCurrency1, liquidity, liquidityTotal);

        // subtract the amount of currency0 and currency1 from the order info
        orderInfo.currency0Total -= amount0;
        orderInfo.currency1Total -= amount1;

        // update total liquidity
        orderInfo.liquidityTotal -= liquidity;

        // unlock the callback to the poolManager, the callback will trigger `unlockCallback`
        // and return the liquidity to the `to` address.
        poolManager.unlock(
            abi.encode(
                CallbackData(
                    CallbackType.Withdraw,
                    abi.encode(WithdrawCallbackData(orderInfo.currency0, orderInfo.currency1, amount0, amount1, to))
                )
            )
        );

        // emit the withdraw event
        emit Withdraw(msg.sender, orderId, liquidity);
    }

    /**
     * @dev Handles callbacks from the `PoolManager` for order operations. Takes encoded `rawData` containing the callback type
     * and operation-specific data. Returns encoded data containing fees accrued for cancel operations, or empty bytes
     * otherwise. Only callable by the PoolManager.
     */
    function unlockCallback(bytes calldata rawData)
        external
        virtual
        override
        onlyPoolManager
        returns (bytes memory returnData)
    {
        CallbackData memory callbackData = abi.decode(rawData, (CallbackData));

        if (callbackData.callbackType == CallbackType.Place) {
            PlaceCallbackData memory placeData = abi.decode(callbackData.data, (PlaceCallbackData));
            (uint256 amount0Fee, uint256 amount1Fee) = _handlePlaceCallback(placeData);
            return abi.encode(amount0Fee, amount1Fee);
        }

        if (callbackData.callbackType == CallbackType.Cancel) {
            CancelCallbackData memory cancelData = abi.decode(callbackData.data, (CancelCallbackData));
            (uint256 amount0Fee, uint256 amount1Fee) = _handleCancelCallback(cancelData);
            return abi.encode(amount0Fee, amount1Fee);
        }

        if (callbackData.callbackType == CallbackType.Withdraw) {
            WithdrawCallbackData memory withdrawData = abi.decode(callbackData.data, (WithdrawCallbackData));
            _handleWithdrawCallback(withdrawData);
            return ZERO_BYTES;
        }
    }

    /**
     * @dev Internal handler for place order callbacks. Takes `placeData` containing the order details and adds the
     * specified liquidity to the pool out of range. Reverts if the order would be placed in range or on the wrong
     * side of the range.
     */
    function _handlePlaceCallback(PlaceCallbackData memory placeData)
        internal
        returns (uint256 amount0Fee, uint256 amount1Fee)
    {
        // get the pool key
        PoolKey memory key = placeData.key;

        // add the out of range liquidity to the pool
        (BalanceDelta principalDelta, BalanceDelta feesAccrued) = poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: placeData.tickLower,
                tickUpper: placeData.tickLower + key.tickSpacing,
                liquidityDelta: int256(uint256(placeData.liquidity)),
                salt: 0
            }),
            ZERO_BYTES
        );

        if (feesAccrued.amount0() > 0) {
            key.currency0.take(poolManager, address(this), amount0Fee = uint256(uint128(feesAccrued.amount0())), true);
        }
        if (feesAccrued.amount1() > 0) {
            key.currency1.take(poolManager, address(this), amount1Fee = uint256(uint128(feesAccrued.amount1())), true);
        }

        BalanceDelta delta = principalDelta - feesAccrued;

        // if the amount of currency0 is negative, the limit order is to sell `currency0` for `currency1`
        if (delta.amount0() < 0) {
            // if the amount of currency1 is not 0, the limit order is in range
            if (delta.amount1() != 0) revert InRange();
            // if `zeroForOne` is false, the limit order is wrong side of the range
            if (!placeData.zeroForOne) revert CrossedRange();

            // settle the currency0 to the owner
            key.currency0.settle(poolManager, placeData.owner, uint256(uint128(-delta.amount0())), false);
        } else {
            // if the amount of currency0 is not 0, the limit order is in range
            if (delta.amount0() != 0) revert InRange();
            // if `zeroForOne` is true, the limit order is wrong side of the range
            if (placeData.zeroForOne) revert CrossedRange();

            // settle the currency1 to the owner
            key.currency1.settle(poolManager, placeData.owner, uint256(uint128(-delta.amount1())), false);
        }
    }

    /**
     * @dev Internal handler for cancel order callbacks. Takes `cancelData` containing the cancellation details and
     * removes liquidity from the pool. Returns accrued fees `(amount0Fee, amount1Fee)` which are allocated to remaining
     * limit order placers, or to the cancelling user if they're removing all liquidity.
     */
    function _handleCancelCallback(CancelCallbackData memory cancelData)
        internal
        returns (uint256 amount0Fee, uint256 amount1Fee)
    {
        // get the tick upper
        int24 tickUpper = cancelData.tickLower + cancelData.key.tickSpacing;

        // remove the liquidity from the pool. The fees accrued by the position are included in the `cancelDelta`
        (BalanceDelta cancelDelta, BalanceDelta feesAccrued) = poolManager.modifyLiquidity(
            cancelData.key,
            ModifyLiquidityParams({
                tickLower: cancelData.tickLower,
                tickUpper: tickUpper,
                liquidityDelta: cancelData.liquidityDelta,
                salt: 0
            }),
            ZERO_BYTES
        );

        BalanceDelta principalDelta;

        // because `modifyPosition` includes not just principal value but also fees, we cannot allocate
        // the proceeds pro-rata. if we were to do so, users who have been in a limit order that's partially filled
        // could be unfairly diluted by a user synchronously placing then canceling a limit order to skim off fees.
        // to prevent this, we allocate all fee revenue to remaining limit order placers, unless this is the last order.
        if (!cancelData.removingAllLiquidity) {
            // if the amount of fees in currency0 is positive, mint currency0 to the hook
            if (feesAccrued.amount0() > 0) {
                poolManager.mint(
                    address(this), cancelData.key.currency0.toId(), amount0Fee = uint128(feesAccrued.amount0())
                );
            }

            // if the amount of fees in currency1 is positive, mint currency1 to the hook
            if (feesAccrued.amount1() > 0) {
                poolManager.mint(
                    address(this), cancelData.key.currency1.toId(), amount1Fee = uint128(feesAccrued.amount1())
                );
            }

            // if the `removingAllLiquidity` flag is false, the fees accrued will be allocated to the remaining limit order placers
            // so we need to subtract the fees from the `cancelDelta` to get the principal delta
            principalDelta = cancelDelta - feesAccrued;
        } else {
            // if the `removingAllLiquidity` flag is true, the fees accrued will be allocated to the placer of the last limit order being cancelled
            // so we can just use the `cancelDelta` as the principal delta
            principalDelta = cancelDelta;
        }

        // if the amount of currency0 is positive, take the currency0 from the pool and send it to the `to` address
        if (principalDelta.amount0() > 0) {
            cancelData.key.currency0.take(poolManager, cancelData.to, uint256(uint128(principalDelta.amount0())), false);
        }

        // if the amount of currency1 is positive, take the currency1 from the pool and send it to the `to` address
        if (principalDelta.amount1() > 0) {
            cancelData.key.currency1.take(poolManager, cancelData.to, uint256(uint128(principalDelta.amount1())), false);
        }
    }

    /**
     * @dev Internal handler for withdraw callbacks. Takes `withdrawData` containing withdrawal amounts and recipient,
     * burns the specified currency amounts from the hook, and transfers them to the recipient address.
     */
    function _handleWithdrawCallback(WithdrawCallbackData memory withdrawData) internal {
        // if the amount of currency0 is positive, burn the currency0 from the hook
        if (withdrawData.currency0Amount > 0) {
            // burn the currency0 from the hook
            poolManager.burn(address(this), withdrawData.currency0.toId(), withdrawData.currency0Amount);
            // take the currency0 from the pool and send it to the `to` address
            poolManager.take(withdrawData.currency0, withdrawData.to, withdrawData.currency0Amount);
        }

        // if the amount of currency1 is positive, burn the currency1 from the hook
        if (withdrawData.currency1Amount > 0) {
            // burn the currency1 from the hook
            poolManager.burn(address(this), withdrawData.currency1.toId(), withdrawData.currency1Amount);
            // take the currency1 from the pool and send it to the `to` address
            poolManager.take(withdrawData.currency1, withdrawData.to, withdrawData.currency1Amount);
        }
    }

    /**
     * @dev Internal handler for filling limit orders when price crosses a tick. Takes a `PoolKey` `key`, target `tickLower`,
     * and direction `zeroForOne`. Removes liquidity from filled orders, mints the received currencies to the hook, and
     * updates order state to track filled amounts.
     */
    function _fillOrder(PoolKey calldata key, int24 tickLower, bool zeroForOne) internal {
        // get the order
        OrderIdLibrary.OrderId orderId = getOrderId(key, tickLower, zeroForOne);

        // if the order is not default (not initialized), fill it
        if (!orderId.equals(ORDER_ID_DEFAULT)) {
            // get the order info
            OrderInfo storage orderInfo = orderInfos[orderId];

            // set the order as filled
            orderInfo.filled = true;

            // set the order as default (inactive)
            setOrderId(key, tickLower, zeroForOne, ORDER_ID_DEFAULT);

            // modify the liquidity to remove the order liquidity from the pool
            (BalanceDelta delta,) = poolManager.modifyLiquidity(
                key,
                ModifyLiquidityParams({
                    tickLower: tickLower,
                    tickUpper: tickLower + key.tickSpacing,
                    liquidityDelta: -int256(uint256(orderInfo.liquidityTotal)),
                    salt: 0
                }),
                ZERO_BYTES
            );

            uint128 amount0;
            uint128 amount1;

            // if the amount of currency0 is positive, mint the currency0 to the hook
            if (delta.amount0() > 0) {
                poolManager.mint(address(this), key.currency0.toId(), amount0 = uint128(delta.amount0()));
            }

            // if the amount of currency1 is positive, mint the currency1 to the hook
            if (delta.amount1() > 0) {
                poolManager.mint(address(this), key.currency1.toId(), amount1 = uint128(delta.amount1()));
            }

            // add the amount of currency0 and currency1 to the order info
            // note that the currency totals must be updated after poolManager calls as they depend on the returned values.
            // This is safe as these functions are only callable on the trusted poolManager
            unchecked {
                // slither-disable-next-line reentrancy-no-eth
                orderInfo.currency0Total += amount0;
                // slither-disable-next-line reentrancy-no-eth
                orderInfo.currency1Total += amount1;
            }

            // emit the fill event
            emit Fill(orderId, key, tickLower, zeroForOne);
        }
    }

    /**
     * @dev Internal helper that calculates the range of ticks crossed during a price change. Takes a `PoolId` `poolId`
     * and `tickSpacing`, returns the current `tickLower` and the range of ticks crossed (`lower`, `upper`) that need
     * to be checked for limit orders.
     */
    function _getCrossedTicks(PoolId poolId, int24 tickSpacing)
        internal
        view
        returns (int24 tickLower, int24 lower, int24 upper)
    {
        tickLower = getTickLower(getTick(poolId), tickSpacing);
        int24 tickLowerLast = getTickLowerLast(poolId);

        if (tickLower < tickLowerLast) {
            lower = tickLower + tickSpacing;
            upper = tickLowerLast;
        } else {
            lower = tickLowerLast;
            upper = tickLower - tickSpacing;
        }
    }

    /**
     * @dev Returns the last recorded lower tick for a given pool. Takes a `PoolId` `poolId` and returns the
     * stored `tickLowerLast` value.
     */
    function getTickLowerLast(PoolId poolId) public view returns (int24) {
        return tickLowerLasts[poolId];
    }

    /**
     * @dev Retrieves the order id for a given pool position. Takes a `PoolKey` `key`, target `tickLower`, and direction
     * `zeroForOne` indicating whether it's buying currency0 or currency1. Returns the {OrderId} associated with this
     * position, or the default order id if no order exists.
     */
    function getOrderId(PoolKey memory key, int24 tickLower, bool zeroForOne)
        public
        view
        returns (OrderIdLibrary.OrderId)
    {
        return orders[keccak256(abi.encode(key, tickLower, zeroForOne))];
    }

    /**
     * @dev Internal helper that updates the order ID mapping. Takes a `PoolKey` `key`, target `tickLower`, direction
     * `zeroForOne`, and `orderId` to store. Associates the given order id with the pool position's hash.
     */
    function setOrderId(PoolKey memory key, int24 tickLower, bool zeroForOne, OrderIdLibrary.OrderId orderId) private {
        orders[keccak256(abi.encode(key, tickLower, zeroForOne))] = orderId;
    }

    /**
     * @dev Get the tick lower. Takes a `tick` and `tickSpacing` and returns the nearest valid tick boundary
     * at or below the input tick, accounting for negative tick handling.
     */
    function getTickLower(int24 tick, int24 tickSpacing) private pure returns (int24) {
        // slither-disable-next-line divide-before-multiply
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed--; // round towards negative infinity
        return compressed * tickSpacing;
    }

    /**
     * @dev Get the liquidity of an order for a given order id and owner. Takes an {OrderId} `orderId` and `owner` address
     * and returns the amount of liquidity the owner has contributed to the order.
     */
    function getOrderLiquidity(OrderIdLibrary.OrderId orderId, address owner) external view returns (uint256) {
        return orderInfos[orderId].liquidity[owner];
    }

    /**
     * @dev Get the current tick for a given pool. Takes a `PoolId` `poolId` and returns the tick calculated
     * from the pool's current sqrt price.
     */
    function getTick(PoolId poolId) private view returns (int24 tick) {
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);
    }

    /**
     * @dev Get the hook permissions for this contract. Returns a `Hooks.Permissions` struct configured to enable
     * `afterInitialize` and `afterSwap` hooks while disabling all other hooks.
     */
    function getHookPermissions() public pure virtual override returns (Hooks.Permissions memory permissions) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
}
