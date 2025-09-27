// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {Position} from "v4-core/src/libraries/Position.sol";
import {LimitOrderHook, OrderIdLibrary} from "src/general/LimitOrderHook.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {FixedPoint128} from "v4-core/src/libraries/FixedPoint128.sol";
import {ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {HookTest} from "test/utils/HookTest.sol";

contract LimitOrderHookTest is HookTest {
    using StateLibrary for IPoolManager;

    LimitOrderHook hook;

    PoolKey noHookKey;

    address user = makeAddr("user");
    address swapper = makeAddr("swapper");
    address attacker = makeAddr("attacker");
    int24 tickSpacing;

    bool filled;
    uint256 currency0Total; // currency0 total in the order
    uint256 currency1Total; // currency1 total in the order
    uint128 liquidityTotal; // liquidity total in the order

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        hook = LimitOrderHook(address(uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_SWAP_FLAG)));

        deployCodeTo("src/general/LimitOrderHook.sol:LimitOrderHook", abi.encode(manager), address(hook));

        (key,) = initPool(currency0, currency1, IHooks(address(hook)), 3000, SQRT_PRICE_1_1);
        (noHookKey,) = initPool(currency0, currency1, IHooks(address(0)), 3000, SQRT_PRICE_1_1);

        tickSpacing = key.tickSpacing;

        IERC20Minimal(Currency.unwrap(currency0)).approve(address(hook), type(uint256).max);
        IERC20Minimal(Currency.unwrap(currency1)).approve(address(hook), type(uint256).max);

        IERC20Minimal(Currency.unwrap(currency0)).transfer(user, 1e30);
        IERC20Minimal(Currency.unwrap(currency1)).transfer(user, 1e30);
        IERC20Minimal(Currency.unwrap(currency0)).transfer(swapper, 1e30);
        IERC20Minimal(Currency.unwrap(currency1)).transfer(swapper, 1e30);
        IERC20Minimal(Currency.unwrap(currency0)).transfer(attacker, 1e30);
        IERC20Minimal(Currency.unwrap(currency1)).transfer(attacker, 1e30);

        vm.startPrank(user);
        IERC20Minimal(Currency.unwrap(currency0)).approve(address(hook), type(uint256).max);
        IERC20Minimal(Currency.unwrap(currency1)).approve(address(hook), type(uint256).max);
        IERC20Minimal(Currency.unwrap(currency0)).approve(address(modifyLiquidityNoChecks), type(uint256).max);
        IERC20Minimal(Currency.unwrap(currency1)).approve(address(modifyLiquidityNoChecks), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(swapper);
        IERC20Minimal(Currency.unwrap(currency0)).approve(address(swapRouter), type(uint256).max);
        IERC20Minimal(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(attacker);
        IERC20Minimal(Currency.unwrap(currency0)).approve(address(hook), type(uint256).max);
        IERC20Minimal(Currency.unwrap(currency1)).approve(address(hook), type(uint256).max);
        IERC20Minimal(Currency.unwrap(currency0)).approve(address(modifyLiquidityNoChecks), type(uint256).max);
        IERC20Minimal(Currency.unwrap(currency1)).approve(address(modifyLiquidityNoChecks), type(uint256).max);
        vm.stopPrank();

        vm.label(Currency.unwrap(currency0), "currency0");
        vm.label(Currency.unwrap(currency1), "currency1");
    }

    function calculateExpectedFees(
        IPoolManager manager,
        PoolId poolId,
        address owner,
        int24 tickLower,
        int24 tickUpper,
        bytes32 salt
    ) internal view returns (int128, int128) {
        bytes32 positionKey = Position.calculatePositionKey(owner, tickLower, tickUpper, salt);
        (uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128) =
            StateLibrary.getPositionInfo(manager, poolId, positionKey);

        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) =
            StateLibrary.getFeeGrowthInside(manager, poolId, tickLower, tickUpper);

        uint256 feesExpected0 =
            FullMath.mulDiv(feeGrowthInside0X128 - feeGrowthInside0LastX128, liquidity, FixedPoint128.Q128);
        uint256 feesExpected1 =
            FullMath.mulDiv(feeGrowthInside1X128 - feeGrowthInside1LastX128, liquidity, FixedPoint128.Q128);

        return (int128(int256(feesExpected0)), int128(int256(feesExpected1)));
    }

    function modifyPoolLiquidityNoChecks(
        PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper,
        int256 liquidity,
        bytes32 salt
    ) internal returns (BalanceDelta) {
        ModifyLiquidityParams memory modifyLiquidityParams =
            ModifyLiquidityParams({tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: liquidity, salt: salt});
        return modifyLiquidityNoChecks.modifyLiquidity(poolKey, modifyLiquidityParams, "");
    }

    function swapOnPool(PoolKey memory poolKey, bool zeroForOne, int256 amountSpecified, uint160 sqrtPriceLimitX96)
        internal
        returns (BalanceDelta)
    {
        return swapRouter.swap(
            poolKey,
            SwapParams({zeroForOne: zeroForOne, amountSpecified: amountSpecified, sqrtPriceLimitX96: sqrtPriceLimitX96}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );
    }

    // Helpers
    function getCurrentTick(PoolId poolId) public view returns (int24 tick) {
        (uint160 sqrtPriceX96,,,) = manager.getSlot0(poolId);
        tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);
    }

    function test_getTickLowerLast() public view {
        assertEq(hook.getTickLowerLast(key.toId()), 0);
    }

    function test_zeroLiquidityRevert() public {
        vm.expectRevert(LimitOrderHook.ZeroLiquidity.selector);
        hook.placeOrder(key, 0, true, 0);
    }

    function test_zeroForOneRightBoundaryOfCurrentRange() public {
        int24 tickLower = 60;
        bool zeroForOne = true;
        uint128 liquidity = 1000000;

        hook.placeOrder(key, tickLower, zeroForOne, liquidity);

        assertTrue(OrderIdLibrary.equals(hook.getOrderId(key, tickLower, zeroForOne), OrderIdLibrary.OrderId.wrap(1)));

        bytes32 positionId = Position.calculatePositionKey(address(hook), tickLower, tickLower + key.tickSpacing, 0);
        assertEq(manager.getPositionLiquidity(key.toId(), positionId), liquidity);
    }

    function test_zeroForOneLeftBoundaryOfCurrentRange() public {
        int24 tickLower = 0;
        bool zeroForOne = true;
        uint128 liquidity = 1000000;

        hook.placeOrder(key, tickLower, zeroForOne, liquidity);

        assertTrue(OrderIdLibrary.equals(hook.getOrderId(key, tickLower, zeroForOne), OrderIdLibrary.OrderId.wrap(1)));

        bytes32 positionId = Position.calculatePositionKey(address(hook), tickLower, tickLower + key.tickSpacing, 0);
        assertEq(manager.getPositionLiquidity(key.toId(), positionId), liquidity);
    }

    function test_zeroForOneCrossedRangeRevert() public {
        vm.expectRevert(LimitOrderHook.CrossedRange.selector);
        hook.placeOrder(key, -60, true, 1000000);
    }

    function test_zeroForOneInRangeRevert() public {
        // swapping is free, there's no liquidity in the pool, so we only need to specify 1 wei
        swapRouter.swap(
            key,
            SwapParams({zeroForOne: false, amountSpecified: -1 ether, sqrtPriceLimitX96: SQRT_PRICE_1_1 + 1}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            bytes("")
        );

        vm.expectRevert(LimitOrderHook.InRange.selector);
        hook.placeOrder(key, 0, true, 1000000);
    }

    function test_notZeroForOneLeftBoundaryOfCurrentRange() public {
        int24 tickLower = -60;
        bool zeroForOne = false;
        uint128 liquidity = 1000000;

        hook.placeOrder(key, tickLower, zeroForOne, liquidity);

        assertTrue(OrderIdLibrary.equals(hook.getOrderId(key, tickLower, zeroForOne), OrderIdLibrary.OrderId.wrap(1)));

        bytes32 positionId = Position.calculatePositionKey(address(hook), tickLower, tickLower + key.tickSpacing, 0);
        assertEq(manager.getPositionLiquidity(key.toId(), positionId), liquidity);
    }

    function test_notZeroForOneCrossedRangeRevert() public {
        vm.expectRevert(LimitOrderHook.CrossedRange.selector);
        hook.placeOrder(key, 0, false, 1000000);
    }

    function test_notZeroForOneInRangeRevert() public {
        // swapping is free, there's no liquidity in the pool, so we only need to specify 1 wei
        swapRouter.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -1 ether, sqrtPriceLimitX96: SQRT_PRICE_1_1 - 1}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            bytes("")
        );

        vm.expectRevert(LimitOrderHook.InRange.selector);
        hook.placeOrder(key, -60, false, 1000000);
    }

    function test_multipleLPs() public {
        int24 tickLower = 60;
        bool zeroForOne = true;
        uint128 liquidity = 1000000;

        hook.placeOrder(key, tickLower, zeroForOne, liquidity);

        vm.startPrank(user);
        hook.placeOrder(key, tickLower, zeroForOne, liquidity);
        vm.stopPrank();

        assertTrue(OrderIdLibrary.equals(hook.getOrderId(key, tickLower, zeroForOne), OrderIdLibrary.OrderId.wrap(1)));

        bytes32 positionId = Position.calculatePositionKey(address(hook), tickLower, tickLower + key.tickSpacing, 0);
        assertEq(manager.getPositionLiquidity(key.toId(), positionId), liquidity * 2);

        Currency orderCurrency0;
        Currency orderCurrency1;
        (filled, orderCurrency0, orderCurrency1, currency0Total, currency1Total, liquidityTotal) =
            hook.orderInfos(OrderIdLibrary.OrderId.wrap(1));
        assertFalse(filled);
        assertTrue(currency0 == orderCurrency0);
        assertTrue(currency1 == orderCurrency1);
        assertEq(currency0Total, 0);
        assertEq(currency1Total, 0);
        assertEq(liquidityTotal, liquidity * 2);
        assertEq(hook.getOrderLiquidity(OrderIdLibrary.OrderId.wrap(1), address(this)), liquidity);
        assertEq(hook.getOrderLiquidity(OrderIdLibrary.OrderId.wrap(1), user), liquidity);
    }

    function test_cancelOrder() public {
        int24 tickLower = 0;
        bool zeroForOne = true;
        uint128 liquidity = 1000000;

        uint256 balanceBefore = currency0.balanceOf(address(this));

        hook.placeOrder(key, tickLower, zeroForOne, liquidity);

        hook.cancelOrder(key, tickLower, zeroForOne, address(this));

        uint256 balanceAfterCancel = currency0.balanceOf(address(this));

        assertApproxEqAbs(balanceBefore, balanceAfterCancel, 1);
    }

    function test_cancelOrder_feesAccrued() public {
        bool zeroForOne = true;
        uint128 liquidity = 1e15;

        hook.placeOrder(key, 0, zeroForOne, liquidity);

        //place order is the same as add liquidity to the pool in the range (0, tickSpacing)
        vm.startPrank(user);
        hook.placeOrder(key, 0, zeroForOne, liquidity);

        // add liquidity equivalent to two orders
        modifyPoolLiquidityNoChecks(noHookKey, 0, key.tickSpacing, int256(uint256(2 * liquidity)), 0);
        vm.stopPrank();

        // this swap should accrue fees to the order, since tick is in range (0, tickSpacing)
        vm.startPrank(swapper);
        swapOnPool(key, false, -1e20, TickMath.getSqrtPriceAtTick(key.tickSpacing / 2));
        swapOnPool(noHookKey, false, -1e20, TickMath.getSqrtPriceAtTick(key.tickSpacing / 2));
        vm.stopPrank();

        (filled,,, currency0Total, currency1Total, liquidityTotal) = hook.orderInfos(OrderIdLibrary.OrderId.wrap(1));

        assertFalse(filled, "order should not be filled");
        assertEq(currency0Total, 0, "currency0Total should be 0");
        assertEq(currency1Total, 0, "currency1Total should be 0");
        assertEq(liquidityTotal, 2 * liquidity, "liquidityTotal should be 2*liquidity");

        int256 balance0Before = int256(currency0.balanceOf(address(this)));
        int256 balance1Before = int256(currency1.balanceOf(address(this)));
        hook.cancelOrder(key, 0, zeroForOne, address(this));
        int256 balance0AfterCancel = int256(currency0.balanceOf(address(this)));
        int256 balance1AfterCancel = int256(currency1.balanceOf(address(this)));

        // cancel the order is the same as remove liquidity from the pool in the range (0, tickSpacing)
        vm.startPrank(user);
        (int128 feesExpected0, int128 feesExpected1) =
            calculateExpectedFees(manager, noHookKey.toId(), address(modifyLiquidityNoChecks), 0, key.tickSpacing, 0);
        BalanceDelta delta = modifyPoolLiquidityNoChecks(noHookKey, 0, key.tickSpacing, -int256(uint256(liquidity)), 0);
        vm.stopPrank();

        (filled,,, currency0Total, currency1Total, liquidityTotal) = hook.orderInfos(OrderIdLibrary.OrderId.wrap(1));

        assertEq(currency0Total, uint256(uint128(feesExpected0)));
        assertEq(currency1Total, uint256(uint128(feesExpected1)));

        assertTrue(feesExpected0 > 0 || feesExpected1 > 0);

        // canceling the order is the same as removing liquidity, minus the fees accrued to the order (which are in currency total)
        assertEq(balance0AfterCancel - balance0Before, int256(delta.amount0()) - int256(currency0Total));
        assertEq(balance1AfterCancel - balance1Before, int256(delta.amount1()) - int256(currency1Total));
    }

    function test_cancelOrder_removingAllLiquidity() public {
        bool zeroForOne = true;
        uint128 liquidity = 1000000;

        // first user places an order
        hook.placeOrder(key, 0, zeroForOne, liquidity);

        // second user places an order
        vm.startPrank(user);
        hook.placeOrder(key, 0, zeroForOne, liquidity);
        // add liquidity equivalent to two orders
        modifyPoolLiquidityNoChecks(noHookKey, 0, key.tickSpacing, int256(uint256(2 * liquidity)), 0);
        vm.stopPrank();

        // this swap should accrue fees to the order, since tick is in range (0, tickSpacing)
        vm.startPrank(swapper);
        swapOnPool(key, false, -1e20, TickMath.getSqrtPriceAtTick(key.tickSpacing / 2));
        swapOnPool(noHookKey, false, -1e20, TickMath.getSqrtPriceAtTick(key.tickSpacing / 2));
        vm.stopPrank();

        // first user cancels the order
        hook.cancelOrder(key, 0, zeroForOne, address(this));

        // now second user cancels the order
        vm.startPrank(user);
        int256 balanceUser0Before = int256(currency0.balanceOf(user));
        int256 balanceUser1Before = int256(currency1.balanceOf(user));
        hook.cancelOrder(key, 0, zeroForOne, user);
        int256 balanceUser0After = int256(currency0.balanceOf(user));
        int256 balanceUser1After = int256(currency1.balanceOf(user));
        vm.stopPrank();

        (filled,,, currency0Total, currency1Total, liquidityTotal) = hook.orderInfos(OrderIdLibrary.OrderId.wrap(1));
        assertEq(filled, false, "order should not be filled");
        assertEq(liquidityTotal, 0, "liquidityTotal should be liquidity");
        assertEq(currency0Total, 0, "currency0Total should be 0");
        assertEq(currency1Total, 0, "currency1Total should be 0");

        // cancel the order is the same as remove liquidity from the pool in the range (0, tickSpacing)
        vm.startPrank(user);
        (int128 feesExpected0, int128 feesExpected1) =
            calculateExpectedFees(manager, noHookKey.toId(), address(modifyLiquidityNoChecks), 0, key.tickSpacing, 0);
        BalanceDelta delta = modifyPoolLiquidityNoChecks(noHookKey, 0, key.tickSpacing, -int256(uint256(liquidity)), 0);
        vm.stopPrank();

        assertTrue(feesExpected0 > 0 || feesExpected1 > 0);

        // all fees accrued go to the last user to cancel the order
        assertEq(balanceUser0After - balanceUser0Before, int256(delta.amount0()) - int256(feesExpected0));
        assertEq(balanceUser1After - balanceUser1Before, int256(delta.amount1()) - int256(feesExpected1));
    }

    function test_placeOrder_feesAccrued() public {
        bool zeroForOne = true;
        uint128 liquidity = 1000000;

        hook.placeOrder(key, 0, zeroForOne, liquidity);

        //place order is the same as add liquidity to the pool in the range (0, tickSpacing)
        vm.startPrank(user);
        hook.placeOrder(key, 0, zeroForOne, liquidity);

        // add liquidity equivalent to two orders
        modifyPoolLiquidityNoChecks(noHookKey, 0, key.tickSpacing, int256(uint256(2 * liquidity)), 0);
        vm.stopPrank();

        // this swap should accrue fees to the order, since tick is in range (0, tickSpacing)
        vm.startPrank(swapper);
        swapOnPool(key, false, -1e20, TickMath.getSqrtPriceAtTick(key.tickSpacing / 2));
        swapOnPool(noHookKey, false, -1e20, TickMath.getSqrtPriceAtTick(key.tickSpacing / 2));

        // swap outside of the range (0, tickSpacing) without filling the order to be able to place orders again
        swapOnPool(noHookKey, true, -1e15, TickMath.getSqrtPriceAtTick(-key.tickSpacing));
        swapOnPool(key, true, -1e15, TickMath.getSqrtPriceAtTick(-key.tickSpacing));

        vm.stopPrank();

        (filled,,, currency0Total, currency1Total, liquidityTotal) = hook.orderInfos(OrderIdLibrary.OrderId.wrap(1));

        assertFalse(filled, "order should not be filled");
        assertEq(currency0Total, 0, "currency0Total should be 0");
        assertEq(currency1Total, 0, "currency1Total should be 0");
        assertEq(liquidityTotal, 2 * liquidity, "liquidityTotal should be 2*liquidity");

        int256 balance0Before = int256(currency0.balanceOf(address(this)));
        int256 balance1Before = int256(currency1.balanceOf(address(this)));
        hook.placeOrder(key, 0, zeroForOne, liquidity);
        int256 balance0AfterPlace = int256(currency0.balanceOf(address(this)));
        int256 balance1AfterPlace = int256(currency1.balanceOf(address(this)));

        // place the order is the same as add liquidity to the pool in the range (0, tickSpacing)

        vm.startPrank(user);
        (int128 feesExpected0, int128 feesExpected1) =
            calculateExpectedFees(manager, noHookKey.toId(), address(modifyLiquidityNoChecks), 0, key.tickSpacing, 0);
        BalanceDelta delta = modifyPoolLiquidityNoChecks(noHookKey, 0, key.tickSpacing, int256(uint256(liquidity)), 0);
        vm.stopPrank();
        (filled,,, currency0Total, currency1Total, liquidityTotal) = hook.orderInfos(OrderIdLibrary.OrderId.wrap(1));

        assertFalse(filled, "order should not be filled");
        assertEq(liquidityTotal, 3 * liquidity, "liquidityTotal should be 3*liquidity");

        assertEq(currency0Total, uint256(uint128(feesExpected0)), "currency0Total should be feesExpected0");
        assertEq(currency1Total, uint256(uint128(feesExpected1)), "currency1Total should be feesExpected1");

        assertTrue(feesExpected0 > 0 || feesExpected1 > 0, "fees should be accrued");

        // placing the order is the same as adding liquidity, plus the fees accrued to the order (which are in currency total)
        assertEq(
            balance0AfterPlace - balance0Before,
            int256(delta.amount0()) - int256(currency0Total),
            "fees were not held in currency0Total"
        );
        assertEq(
            balance1AfterPlace - balance1Before,
            int256(delta.amount1()) - int256(currency1Total),
            "fees were not held in currency1Total"
        );
    }

    function test_withdraw_multipleLPs() public {
        int24 tickLower = 0;
        bool zeroForOne = true;
        uint128 liquidity = 1000000;

        hook.placeOrder(key, tickLower, zeroForOne, liquidity);

        currency0.transfer(user, 1e18);
        currency1.transfer(user, 1e18);

        vm.startPrank(user);
        hook.placeOrder(key, tickLower, zeroForOne, liquidity);
        vm.stopPrank();

        assertTrue(OrderIdLibrary.equals(hook.getOrderId(key, tickLower, zeroForOne), OrderIdLibrary.OrderId.wrap(1)));

        bytes32 positionId = Position.calculatePositionKey(address(hook), tickLower, tickLower + key.tickSpacing, 0);
        assertEq(manager.getPositionLiquidity(key.toId(), positionId), liquidity * 2);

        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: false,
                amountSpecified: -1e18,
                sqrtPriceLimitX96: TickMath.getSqrtPriceAtTick(tickLower + key.tickSpacing)
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );

        (filled,,, currency0Total, currency1Total,) = hook.orderInfos(OrderIdLibrary.OrderId.wrap(1));

        assertTrue(filled, "order should be filled");
        assertEq(currency0Total, 0, "wrong amount of currency0");
        assertEq(currency1Total, 2 * (2996 + 17), "wrong amount of currency1");

        vm.startPrank(user);
        hook.withdraw(OrderIdLibrary.OrderId.wrap(1), user);
        vm.stopPrank();

        (filled,,, currency0Total, currency1Total,) = hook.orderInfos(OrderIdLibrary.OrderId.wrap(1));

        assertTrue(filled, "order should be filled");
        assertEq(currency0Total, 0, "wrong amount of currency0");
        assertEq(currency1Total, 2996 + 17, "wrong amount of currency1");

        hook.withdraw(OrderIdLibrary.OrderId.wrap(1), address(this));

        (filled,,, currency0Total, currency1Total,) = hook.orderInfos(OrderIdLibrary.OrderId.wrap(1));

        assertTrue(filled, "order should be filled");
        assertEq(currency0Total, 0, "wrong amount of currency0");
        assertEq(currency1Total, 0, "wrong amount of currency1");
    }

    function test_withdraw_feesAccruedFromCancel() public {
        bool zeroForOne = true;
        uint128 liquidity = 1000000;

        // first user places an order
        hook.placeOrder(key, 0, zeroForOne, liquidity);

        // second user places an order
        vm.startPrank(user);
        hook.placeOrder(key, 0, zeroForOne, liquidity);
        // add liquidity equivalent to two orders
        modifyPoolLiquidityNoChecks(noHookKey, 0, key.tickSpacing, int256(uint256(2 * liquidity)), 0);
        vm.stopPrank();

        // this swap should accrue fees to the order, since tick is in range (0, tickSpacing)
        vm.startPrank(swapper);
        swapOnPool(key, false, -1e20, TickMath.getSqrtPriceAtTick(key.tickSpacing / 2));
        swapOnPool(noHookKey, false, -1e20, TickMath.getSqrtPriceAtTick(key.tickSpacing / 2));
        vm.stopPrank();

        // first user cancels the order
        hook.cancelOrder(key, 0, zeroForOne, address(this));

        vm.startPrank(user);
        (int128 initialFeesExpected0, int128 initialFeesExpected1) =
            calculateExpectedFees(manager, noHookKey.toId(), address(modifyLiquidityNoChecks), 0, key.tickSpacing, 0);
        BalanceDelta delta = modifyPoolLiquidityNoChecks(noHookKey, 0, key.tickSpacing, -int256(uint256(liquidity)), 0);
        vm.stopPrank();

        assertTrue(initialFeesExpected0 > 0 || initialFeesExpected1 > 0, "fees should be accrued");

        (filled,,, currency0Total, currency1Total, liquidityTotal) = hook.orderInfos(OrderIdLibrary.OrderId.wrap(1));

        assertFalse(filled, "order should not be filled");
        assertEq(liquidityTotal, liquidity, "liquidityTotal should be liquidity");
        assertEq(currency0Total, uint256(uint128(initialFeesExpected0)), "currency0Total should be feesExpected0");
        assertEq(currency1Total, uint256(uint128(initialFeesExpected1)), "currency1Total should be feesExpected1");

        // this swap should fill the order, cross the range (0, tickSpacing)
        vm.startPrank(swapper);
        swapOnPool(key, false, -1e20, TickMath.getSqrtPriceAtTick(2 * key.tickSpacing));
        swapOnPool(noHookKey, false, -1e20, TickMath.getSqrtPriceAtTick(2 * key.tickSpacing));
        vm.stopPrank();

        // second user withdraws the order
        vm.startPrank(user);
        int256 balanceUser0Before = int256(currency0.balanceOf(user));
        int256 balanceUser1Before = int256(currency1.balanceOf(user));
        hook.withdraw(OrderIdLibrary.OrderId.wrap(1), user);
        int256 balanceUser0After = int256(currency0.balanceOf(user));
        int256 balanceUser1After = int256(currency1.balanceOf(user));
        vm.stopPrank();

        (filled,,, currency0Total, currency1Total, liquidityTotal) = hook.orderInfos(OrderIdLibrary.OrderId.wrap(1));

        assertTrue(filled, "order should be filled");
        assertEq(currency0Total, 0, "currency0Total should be 0");
        assertEq(currency1Total, 0, "currency1Total should be 0");
        assertEq(liquidityTotal, 0, "liquidityTotal should be 0");

        // cancel the order is the same as remove liquidity from the pool in the range (0, tickSpacing)
        vm.startPrank(user);
        delta = modifyPoolLiquidityNoChecks(noHookKey, 0, key.tickSpacing, -int256(uint256(liquidity)), 0);
        vm.stopPrank();

        // the fees are added to the balance of the user who withdraws the order
        assertEq(balanceUser0After - balanceUser0Before, int256(delta.amount0()) + int256(initialFeesExpected0));
        assertEq(balanceUser1After - balanceUser1Before, int256(delta.amount1()) + int256(initialFeesExpected1));
    }

    function test_withdraw_feesAccruedJIT() public {
        // some user places an order
        hook.placeOrder(key, 0, true, 1e15);

        // user places the same order as the first user
        vm.startPrank(user);
        hook.placeOrder(key, 0, true, 1e15);
        // add liquidity equivalent to 2 orders
        modifyPoolLiquidityNoChecks(noHookKey, 0, key.tickSpacing, int256(uint256(2 * 1e15)), 0);
        vm.stopPrank();

        vm.startPrank(swapper);
        // this swap should accrue fees to the order, since tick is in range (0, tickSpacing)
        swapOnPool(key, false, -1e20, TickMath.getSqrtPriceAtTick(tickSpacing / 2));
        swapOnPool(noHookKey, false, -1e20, TickMath.getSqrtPriceAtTick(tickSpacing / 2));

        // swap outside of the range (0, tickSpacing) without filling the order to be able to place orders again
        swapOnPool(key, true, -1e15, TickMath.getSqrtPriceAtTick(-tickSpacing));
        swapOnPool(noHookKey, true, -1e15, TickMath.getSqrtPriceAtTick(-tickSpacing));
        vm.stopPrank();

        // some user cancels the order, which accrues fees to the order
        hook.cancelOrder(key, 0, true, address(this));

        // attacker places the same order as the first user
        vm.startPrank(attacker);
        hook.placeOrder(key, 0, true, 1e15);
        vm.stopPrank();

        // add liquidity to be equivalent as placing the order
        vm.startPrank(user);
        (int128 initialFeesExpected0, int128 initialFeesExpected1) =
            calculateExpectedFees(manager, noHookKey.toId(), address(modifyLiquidityNoChecks), 0, tickSpacing, 0);
        modifyPoolLiquidityNoChecks(noHookKey, 0, tickSpacing, int256(uint256(1e15)), 0);
        vm.stopPrank();

        vm.startPrank(user);
        BalanceDelta delta = modifyPoolLiquidityNoChecks(noHookKey, 0, tickSpacing, -int256(uint256(1e15)), 0);
        vm.stopPrank();

        assertTrue(initialFeesExpected0 > 0 || initialFeesExpected1 > 0, "fees should be accrued");

        (filled,,, currency0Total, currency1Total, liquidityTotal) = hook.orderInfos(OrderIdLibrary.OrderId.wrap(1));

        assertFalse(filled, "order should not be filled");
        assertEq(liquidityTotal, 1e15 * 2, "liquidityTotal should be 2 * liquidity");
        assertApproxEqAbs(
            currency0Total, uint256(uint128(initialFeesExpected0)), 1, "currency0Total should be the fees accrued"
        );
        assertApproxEqAbs(
            currency1Total, uint256(uint128(initialFeesExpected1)), 1, "currency1Total should be the fees accrued"
        );

        // this swap should fill the order, cross the range (0, tickSpacing)
        vm.startPrank(swapper);
        swapOnPool(key, false, -1e20, TickMath.getSqrtPriceAtTick(2 * tickSpacing));
        swapOnPool(noHookKey, false, -1e20, TickMath.getSqrtPriceAtTick(2 * tickSpacing));
        vm.stopPrank();

        vm.startPrank(user);
        delta = modifyPoolLiquidityNoChecks(noHookKey, 0, tickSpacing, -int256(uint256(2 * 1e15)), 0);
        vm.stopPrank();

        (,,, currency0Total, currency1Total,) = hook.orderInfos(OrderIdLibrary.OrderId.wrap(1));

        // currency on the hook should be delta
        assertEq(
            currency0Total,
            uint256(uint128(delta.amount0())) + uint256(uint128(initialFeesExpected0)),
            "currency0Total should be the delta.amount0() + initialFeesExpected0"
        );
        assertEq(
            currency1Total,
            uint256(uint128(delta.amount1())) + uint256(uint128(initialFeesExpected1)),
            "currency1Total should be the delta.amount1() + initialFeesExpected1"
        );

        // attacker withdraws the order
        vm.startPrank(attacker);
        int256 balanceAttacker0Before = int256(currency0.balanceOf(attacker));
        int256 balanceAttacker1Before = int256(currency1.balanceOf(attacker));
        hook.withdraw(OrderIdLibrary.OrderId.wrap(1), attacker);
        int256 balanceAttacker0After = int256(currency0.balanceOf(attacker));
        int256 balanceAttacker1After = int256(currency1.balanceOf(attacker));
        vm.stopPrank();

        uint256 currency0Total2;
        uint256 currency1Total2;

        (filled,,, currency0Total2, currency1Total2, liquidityTotal) = hook.orderInfos(OrderIdLibrary.OrderId.wrap(1));

        assertTrue(filled, "order should be filled");
        assertEq(liquidityTotal, 1e15, "liquidityTotal should be liquidity");
        assertApproxEqAbs(currency0Total2, currency0Total, 1, "attacker should not withdraw fees accrued");
        assertApproxEqAbs(
            currency1Total2,
            currency1Total / 2 + uint256(uint128(initialFeesExpected1)) / 2,
            1,
            "attacker should not withdraw fees accrued"
        );

        // cancel the order is the same as remove liquidity from the pool in the range (0, tickSpacing)
        vm.startPrank(user);

        int256 balanceUser0BeforeWithdraw = int256(currency0.balanceOf(user));
        int256 balanceUser1BeforeWithdraw = int256(currency1.balanceOf(user));
        hook.withdraw(OrderIdLibrary.OrderId.wrap(1), user);
        int256 balanceUser0AfterWithdraw = int256(currency0.balanceOf(user));
        int256 balanceUser1AfterWithdraw = int256(currency1.balanceOf(user));
        vm.stopPrank();

        (,,, currency0Total, currency1Total, liquidityTotal) = hook.orderInfos(OrderIdLibrary.OrderId.wrap(1));

        assertEq(liquidityTotal, 0, "liquidityTotal should be 0");
        assertEq(currency0Total, 0, "currency0Total should be 0");
        assertEq(currency1Total, 0, "currency1Total should be 0");

        assertApproxEqAbs(
            balanceAttacker0After - balanceAttacker0Before,
            balanceUser0AfterWithdraw - balanceUser0BeforeWithdraw - int256(uint256(uint128(initialFeesExpected0))),
            1,
            "fees should go to the user who withdraws the order"
        );
        assertApproxEqAbs(
            balanceAttacker1After - balanceAttacker1Before,
            balanceUser1AfterWithdraw - balanceUser1BeforeWithdraw - int256(uint256(uint128(initialFeesExpected1))),
            1,
            "fees should go to the user who withdraws the order"
        );
    }

    function test_swapAcrossRange() public {
        int24 tickLower = 0;
        bool zeroForOne = true;
        uint128 liquidity = 1000000;

        hook.placeOrder(key, tickLower, zeroForOne, liquidity);

        int24 currentTick = getCurrentTick(key.toId());

        assertEq(currentTick, tickLower, "Initial tick is wrong");

        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -1e17,
                sqrtPriceLimitX96: TickMath.getSqrtPriceAtTick(tickLower - 10 * key.tickSpacing)
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );

        currentTick = getCurrentTick(key.toId());
        assertEq(currentTick, tickLower - 10 * key.tickSpacing, "Tick after swap 1 is wrong");

        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: false,
                amountSpecified: -1e17,
                sqrtPriceLimitX96: TickMath.getSqrtPriceAtTick(tickLower + key.tickSpacing / 2)
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );

        currentTick = getCurrentTick(key.toId());
        assertEq(currentTick, tickLower + key.tickSpacing / 2, "Tick after swap 2 is wrong");

        (filled,,, currency0Total, currency1Total,) = hook.orderInfos(OrderIdLibrary.OrderId.wrap(1));

        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -1e17,
                sqrtPriceLimitX96: TickMath.getSqrtPriceAtTick(tickLower - key.tickSpacing / 2)
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );

        (filled,,, currency0Total, currency1Total,) = hook.orderInfos(OrderIdLibrary.OrderId.wrap(1));

        assertFalse(filled, "order should be filled");
        assertEq(currency0Total, 0, "wrong amount of currency0");
        assertEq(currency1Total, 0, "wrong amount of currency1"); // 3013, 2 wei of dust

        bytes32 positionId = Position.calculatePositionKey(address(hook), tickLower, tickLower + key.tickSpacing, 0);
        assertEq(manager.getPositionLiquidity(key.toId(), positionId), liquidity);

        vm.expectRevert(LimitOrderHook.NotFilled.selector);
        hook.withdraw(OrderIdLibrary.OrderId.wrap(1), address(this));
    }
}
