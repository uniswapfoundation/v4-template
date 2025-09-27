// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {BaseCustomCurveMock} from "test/mocks/BaseCustomCurveMock.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {BaseCustomAccounting} from "src/base/BaseCustomAccounting.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";

contract BaseCustomCurveTest is Test, Deployers {
    using SafeCast for uint256;
    using StateLibrary for IPoolManager;

    event Swap(
        PoolId indexed poolId,
        address indexed sender,
        int128 amount0,
        int128 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick,
        uint24 fee
    );

    BaseCustomCurveMock hook;

    uint256 constant MAX_DEADLINE = 12329839823;

    // Minimum and maximum ticks for a spacing of 60
    int24 constant MIN_TICK = -887220;
    int24 constant MAX_TICK = 887220;

    PoolId id;

    function setUp() public {
        deployFreshManagerAndRouters();

        hook = BaseCustomCurveMock(
            payable(
                address(
                    uint160(
                        Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                            | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
                    )
                )
            )
        );
        deployCodeTo("test/mocks/BaseCustomCurveMock.sol:BaseCustomCurveMock", abi.encode(manager), address(hook));

        deployMintAndApprove2Currencies();
        (key, id) = initPool(currency0, currency1, IHooks(address(hook)), LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1);

        ERC20(Currency.unwrap(currency0)).approve(address(hook), type(uint256).max);
        ERC20(Currency.unwrap(currency1)).approve(address(hook), type(uint256).max);

        vm.label(Currency.unwrap(currency0), "currency0");
        vm.label(Currency.unwrap(currency1), "currency1");
    }

    function test_beforeInitialize_poolKey_succeeds() public view {
        (Currency _currency0, Currency _currency1, uint24 _fee, int24 _tickSpacing, IHooks _hooks) = hook.poolKey();

        assertEq(Currency.unwrap(_currency0), Currency.unwrap(currency0));
        assertEq(Currency.unwrap(_currency1), Currency.unwrap(currency1));
        assertEq(_fee, LPFeeLibrary.DYNAMIC_FEE_FLAG);
        assertEq(_tickSpacing, 60);
        assertEq(address(_hooks), address(hook));
    }

    function test_initialize_already_reverts() public {
        vm.expectRevert();
        initPool(currency0, currency1, IHooks(address(hook)), LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1);
    }

    function test_addLiquidity_succeeds() public {
        uint256 prevBalance0 = key.currency0.balanceOf(address(this));
        uint256 prevBalance1 = key.currency1.balanceOf(address(this));

        BaseCustomAccounting.AddLiquidityParams memory addLiquidityParams = BaseCustomAccounting.AddLiquidityParams(
            10 ether, 10 ether, 9 ether, 9 ether, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0)
        );

        hook.addLiquidity(addLiquidityParams);

        uint256 liquidityTokenBal = hook.balanceOf(address(this));

        assertEq(key.currency0.balanceOf(address(this)), prevBalance0 - 10 ether);
        assertEq(key.currency1.balanceOf(address(this)), prevBalance1 - 10 ether);

        assertEq(liquidityTokenBal, 10 ether);
    }

    function test_addLiquidity_native_succeeds() public {
        BaseCustomCurveMock nativeHook = BaseCustomCurveMock(payable(0x1000000000000000000000000000000000002A88));
        deployCodeTo("test/mocks/BaseCustomCurveMock.sol:BaseCustomCurveMock", abi.encode(manager), address(nativeHook));
        (key, id) = initPool(
            CurrencyLibrary.ADDRESS_ZERO,
            currency1,
            IHooks(address(nativeHook)),
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            SQRT_PRICE_1_1
        );

        ERC20(Currency.unwrap(currency1)).approve(address(nativeHook), type(uint256).max);
        vm.label(address(0), "native");

        deal(address(this), 10 ether);

        uint256 prevBalance0 = address(this).balance;
        uint256 prevBalance1 = key.currency1.balanceOf(address(this));

        BaseCustomAccounting.AddLiquidityParams memory addLiquidityParams = BaseCustomAccounting.AddLiquidityParams(
            10 ether, 10 ether, 9 ether, 9 ether, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0)
        );

        nativeHook.addLiquidity{value: 10 ether}(addLiquidityParams);

        uint256 liquidityTokenBal = nativeHook.balanceOf(address(this));

        assertEq(address(this).balance, prevBalance0 - 10 ether);
        assertEq(key.currency1.balanceOf(address(this)), prevBalance1 - 10 ether);

        assertEq(liquidityTokenBal, 10 ether);
    }

    function test_addLiquidity_fuzz_succeeds(uint112 amount) public {
        vm.assume(amount > 0);

        hook.addLiquidity(
            BaseCustomAccounting.AddLiquidityParams(amount, amount, 0, 0, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0))
        );

        uint256 liquidityTokenBal = hook.balanceOf(address(this));
        assertEq(liquidityTokenBal, amount);
    }

    function test_addLiquidity_swapThenAdd_succeeds() public {
        uint256 prevBalance0 = key.currency0.balanceOf(address(this));
        uint256 prevBalance1 = key.currency1.balanceOf(address(this));

        hook.addLiquidity(
            BaseCustomAccounting.AddLiquidityParams(
                10 ether, 10 ether, 9 ether, 9 ether, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0)
            )
        );

        uint256 liquidityTokenBal = hook.balanceOf(address(this));

        assertEq(liquidityTokenBal, 10 ether);
        assertEq(key.currency0.balanceOf(address(this)), prevBalance0 - 10 ether);
        assertEq(key.currency1.balanceOf(address(this)), prevBalance1 - 10 ether);

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(id, address(swapRouter), 0, 0, 79228162514264337593543950336, 0, 0, 0);

        SwapParams memory params =
            SwapParams({zeroForOne: true, amountSpecified: -1 ether, sqrtPriceLimitX96: SQRT_PRICE_1_2});
        PoolSwapTest.TestSettings memory settings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        swapRouter.swap(key, params, settings, ZERO_BYTES);

        assertEq(key.currency0.balanceOf(address(this)), prevBalance0 - 10 ether - 1 ether);
        assertEq(key.currency1.balanceOf(address(this)), prevBalance1 - 9 ether);

        hook.addLiquidity(
            BaseCustomAccounting.AddLiquidityParams(
                5 ether, 5 ether, 4 ether, 4 ether, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0)
            )
        );

        liquidityTokenBal = hook.balanceOf(address(this));

        assertEq(liquidityTokenBal, 15 ether);
        assertEq(liquidityTokenBal, 15 ether);
    }

    function test_addLiquidity_expired_revert() public {
        vm.expectRevert(BaseCustomAccounting.ExpiredPastDeadline.selector);
        hook.addLiquidity(
            BaseCustomAccounting.AddLiquidityParams(0, 0, 0, 0, block.timestamp - 1, MIN_TICK, MAX_TICK, bytes32(0))
        );
    }

    function test_addLiquidity_tooMuchSlippage_reverts() public {
        vm.expectRevert(BaseCustomAccounting.TooMuchSlippage.selector);
        hook.addLiquidity(
            BaseCustomAccounting.AddLiquidityParams(
                10 ether, 10 ether, 100000 ether, 100000 ether, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0)
            )
        );
    }

    function test_removeLiquidity_tooMuchSlippage_reverts() public {
        hook.addLiquidity(
            BaseCustomAccounting.AddLiquidityParams(
                10 ether, 10 ether, 0, 0, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0)
            )
        );

        vm.expectRevert(BaseCustomAccounting.TooMuchSlippage.selector);
        hook.removeLiquidity(
            BaseCustomAccounting.RemoveLiquidityParams(
                10 ether, 6 ether, 6 ether, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0)
            )
        );

        hook.removeLiquidity(
            BaseCustomAccounting.RemoveLiquidityParams(
                10 ether, 4 ether, 4 ether, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0)
            )
        );
    }

    function test_swap_twoSwaps_succeeds() public {
        hook.addLiquidity(
            BaseCustomAccounting.AddLiquidityParams(
                2 ether, 2 ether, 0, 0, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0)
            )
        );

        SwapParams memory params =
            SwapParams({zeroForOne: true, amountSpecified: 1 ether, sqrtPriceLimitX96: MIN_PRICE_LIMIT});
        PoolSwapTest.TestSettings memory settings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        swapRouter.swap(key, params, settings, ZERO_BYTES);
        swapRouter.swap(key, params, settings, ZERO_BYTES);
    }

    function test_removeLiquidity_initialRemove_succeeds() public {
        hook.addLiquidity(
            BaseCustomAccounting.AddLiquidityParams(
                100 ether, 100 ether, 99 ether, 99 ether, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0)
            )
        );

        uint256 prevBalance0 = key.currency0.balanceOf(address(this));
        uint256 prevBalance1 = key.currency1.balanceOf(address(this));

        hook.approve(address(hook), type(uint256).max);

        BaseCustomAccounting.RemoveLiquidityParams memory removeLiquidityParams =
            BaseCustomAccounting.RemoveLiquidityParams(1 ether, 0, 0, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0));

        hook.removeLiquidity(removeLiquidityParams);

        uint256 liquidityTokenBal = hook.balanceOf(address(this));
        assertEq(liquidityTokenBal, 99 ether);
        assertEq(key.currency0.balanceOf(address(this)), prevBalance0 + 0.5 ether);
        assertEq(key.currency1.balanceOf(address(this)), prevBalance1 + 0.5 ether);
    }

    function test_removeLiquidity_fuzz_succeeds(uint256 amount) public {
        vm.assume(amount > 0);

        if (amount > hook.balanceOf(address(this))) {
            vm.expectRevert();
            hook.removeLiquidity(
                BaseCustomAccounting.RemoveLiquidityParams(amount, 0, 0, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0))
            );
        } else {
            uint256 prevLiquidityTokenBal = hook.balanceOf(address(this));
            hook.removeLiquidity(
                BaseCustomAccounting.RemoveLiquidityParams(amount, 0, 0, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0))
            );

            uint256 liquidityTokenBal = hook.balanceOf(address(this));

            assertEq(prevLiquidityTokenBal - liquidityTokenBal, amount);
            assertEq(manager.getLiquidity(id), liquidityTokenBal);
        }
    }

    function test_removeLiquidity_noLiquidity_reverts() public {
        vm.expectRevert();
        hook.removeLiquidity(
            BaseCustomAccounting.RemoveLiquidityParams(
                1000000 ether, 0, 0, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0)
            )
        );
    }

    function test_removeLiquidity_partial_succeeds() public {
        uint256 prevBalance0 = key.currency0.balanceOf(address(this));
        uint256 prevBalance1 = key.currency1.balanceOf(address(this));

        hook.addLiquidity(
            BaseCustomAccounting.AddLiquidityParams(
                10 ether, 10 ether, 9 ether, 9 ether, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0)
            )
        );

        assertEq(hook.balanceOf(address(this)), 10 ether);
        assertEq(key.currency0.balanceOfSelf(), prevBalance0 - 10 ether);
        assertEq(key.currency1.balanceOfSelf(), prevBalance1 - 10 ether);

        hook.removeLiquidity(
            BaseCustomAccounting.RemoveLiquidityParams(5 ether, 0, 0, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0))
        );

        uint256 liquidityTokenBal = hook.balanceOf(address(this));
        assertEq(liquidityTokenBal, 5 ether);
        assertEq(key.currency0.balanceOf(address(this)), prevBalance0 - 7.5 ether);
        assertEq(key.currency1.balanceOf(address(this)), prevBalance1 - 7.5 ether);
    }

    function test_removeLiquidity_diffRatios_succeeds() public {
        uint256 prevBalance0 = key.currency0.balanceOf(address(this));
        uint256 prevBalance1 = key.currency1.balanceOf(address(this));

        hook.addLiquidity(
            BaseCustomAccounting.AddLiquidityParams(
                10 ether, 10 ether, 9 ether, 9 ether, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0)
            )
        );

        assertEq(key.currency0.balanceOf(address(this)), prevBalance0 - 10 ether);
        assertEq(key.currency1.balanceOf(address(this)), prevBalance1 - 10 ether);
        assertEq(hook.balanceOf(address(this)), 10 ether);

        hook.addLiquidity(
            BaseCustomAccounting.AddLiquidityParams(
                5 ether, 2.5 ether, 2 ether, 2 ether, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0)
            )
        );

        assertEq(key.currency0.balanceOf(address(this)), prevBalance0 - 15 ether);
        assertEq(key.currency1.balanceOf(address(this)), prevBalance1 - 12.5 ether);
        assertEq(hook.balanceOf(address(this)), 13.75 ether);

        hook.removeLiquidity(
            BaseCustomAccounting.RemoveLiquidityParams(5 ether, 0, 0, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0))
        );

        uint256 liquidityTokenBal = hook.balanceOf(address(this));
        assertEq(liquidityTokenBal, 8.75 ether);
        assertEq(key.currency0.balanceOf(address(this)), prevBalance0 - 12.5 ether);
        assertEq(key.currency1.balanceOf(address(this)), prevBalance1 - 10 ether);
    }

    function test_removeLiquidity_allFuzz_succeeds(uint112 amount) public {
        vm.assume(amount > 0);

        hook.addLiquidity(
            BaseCustomAccounting.AddLiquidityParams(amount, amount, 0, 0, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0))
        );

        uint256 liquidityTokenBal = hook.balanceOf(address(this));

        hook.removeLiquidity(
            BaseCustomAccounting.RemoveLiquidityParams(
                liquidityTokenBal, 0, 0, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0)
            )
        );

        assertEq(manager.getLiquidity(id), 0);
    }

    function test_removeLiquidity_native_succeeds() public {
        BaseCustomCurveMock nativeHook = BaseCustomCurveMock(payable(0x1000000000000000000000000000000000002A88));
        deployCodeTo("test/mocks/BaseCustomCurveMock.sol:BaseCustomCurveMock", abi.encode(manager), address(nativeHook));
        (key, id) = initPool(
            CurrencyLibrary.ADDRESS_ZERO,
            currency1,
            IHooks(address(nativeHook)),
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            SQRT_PRICE_1_1
        );

        ERC20(Currency.unwrap(currency1)).approve(address(nativeHook), type(uint256).max);
        vm.label(address(0), "native");

        deal(address(this), 10 ether);

        uint256 prevBalance0 = address(this).balance;
        uint256 prevBalance1 = key.currency1.balanceOf(address(this));

        nativeHook.addLiquidity{value: 10 ether}(
            BaseCustomAccounting.AddLiquidityParams(
                10 ether, 10 ether, 9 ether, 9 ether, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0)
            )
        );

        uint256 liquidityTokenBal = nativeHook.balanceOf(address(this));

        nativeHook.removeLiquidity(
            BaseCustomAccounting.RemoveLiquidityParams(
                liquidityTokenBal, 0, 0, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0)
            )
        );

        assertEq(manager.getLiquidity(id), 0);

        assertEq(address(this).balance, prevBalance0 - 5 ether);
        assertEq(key.currency1.balanceOf(address(this)), prevBalance1 - 5 ether);
    }

    function test_removeLiquidity_multiple_succeeds() public {
        // Mint tokens for dummy addresses
        deal(Currency.unwrap(currency0), address(1), 2 ** 128);
        deal(Currency.unwrap(currency1), address(1), 2 ** 128);
        deal(Currency.unwrap(currency0), address(2), 2 ** 128);
        deal(Currency.unwrap(currency1), address(2), 2 ** 128);

        // Approve the hook
        vm.prank(address(1));
        ERC20(Currency.unwrap(currency0)).approve(address(hook), type(uint256).max);
        vm.prank(address(1));
        ERC20(Currency.unwrap(currency1)).approve(address(hook), type(uint256).max);

        vm.prank(address(2));
        ERC20(Currency.unwrap(currency0)).approve(address(hook), type(uint256).max);
        vm.prank(address(2));
        ERC20(Currency.unwrap(currency1)).approve(address(hook), type(uint256).max);

        // address(1) adds liquidity
        vm.prank(address(1));
        hook.addLiquidity(
            BaseCustomAccounting.AddLiquidityParams(
                100 ether, 100 ether, 99 ether, 99 ether, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0)
            )
        );

        // address(2) adds liquidity
        vm.prank(address(2));
        hook.addLiquidity(
            BaseCustomAccounting.AddLiquidityParams(
                100 ether, 100 ether, 99 ether, 99 ether, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0)
            )
        );

        SwapParams memory params =
            SwapParams({zeroForOne: true, amountSpecified: 100 ether, sqrtPriceLimitX96: SQRT_PRICE_1_4});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        // Test contract removes liquidity, succeeds
        hook.removeLiquidity(
            BaseCustomAccounting.RemoveLiquidityParams(
                hook.balanceOf(address(this)), 0, 0, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0)
            )
        );

        // PoolManager does not have any liquidity left over
        assertEq(manager.getLiquidity(id), 0);
    }

    function test_removeLiquidity_swapRemoveAllFuzz_succeeds(uint112 amount) public {
        vm.assume(amount > 4);

        hook.addLiquidity(
            BaseCustomAccounting.AddLiquidityParams(amount, amount, 0, 0, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0))
        );

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: (FullMath.mulDiv(amount, 1, 4)).toInt256(),
            sqrtPriceLimitX96: SQRT_PRICE_1_4
        });

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        uint256 liquidityTokenBal = hook.balanceOf(address(this));

        hook.removeLiquidity(
            BaseCustomAccounting.RemoveLiquidityParams(
                liquidityTokenBal, 0, 0, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0)
            )
        );

        assertEq(manager.getLiquidity(id), 0);
    }

    function test_removeLiquidity_notInitialized_reverts() public {
        BaseCustomCurveMock uninitializedHook = BaseCustomCurveMock(payable(0x1000000000000000000000000000000000002A88));
        deployCodeTo(
            "test/mocks/BaseCustomCurveMock.sol:BaseCustomCurveMock", abi.encode(manager), address(uninitializedHook)
        );

        vm.expectRevert(BaseCustomAccounting.PoolNotInitialized.selector);
        uninitializedHook.removeLiquidity(
            BaseCustomAccounting.RemoveLiquidityParams(1 ether, 0, 0, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0))
        );
    }

    function test_addLiquidity_notInitialized_reverts() public {
        BaseCustomCurveMock uninitializedHook = BaseCustomCurveMock(payable(0x1000000000000000000000000000000000002A88));
        deployCodeTo(
            "test/mocks/BaseCustomCurveMock.sol:BaseCustomCurveMock", abi.encode(manager), address(uninitializedHook)
        );

        vm.expectRevert(BaseCustomAccounting.PoolNotInitialized.selector);
        uninitializedHook.addLiquidity(
            BaseCustomAccounting.AddLiquidityParams(
                1 ether, 1 ether, 0, 0, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0)
            )
        );
    }

    function test_swap_addThenRemove_succeeds() public {
        uint256 prevBalance0 = key.currency0.balanceOf(address(this));
        uint256 prevBalance1 = key.currency1.balanceOf(address(this));

        hook.addLiquidity(
            BaseCustomAccounting.AddLiquidityParams(0, 1 ether, 0, 0, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0))
        );

        uint256 liquidityTokenBal = hook.balanceOf(address(this));

        assertEq(liquidityTokenBal, 0.5 ether);
        assertEq(key.currency0.balanceOf(address(this)), prevBalance0);
        assertEq(key.currency1.balanceOf(address(this)), prevBalance1 - 1 ether);

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(id, address(swapRouter), 0, 0, 79228162514264337593543950336, 0, 0, 0);

        SwapParams memory params =
            SwapParams({zeroForOne: true, amountSpecified: -0.5 ether, sqrtPriceLimitX96: SQRT_PRICE_1_2});
        PoolSwapTest.TestSettings memory settings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        swapRouter.swap(key, params, settings, ZERO_BYTES);

        assertEq(key.currency0.balanceOf(address(this)), prevBalance0 - 0.5 ether);
        assertEq(key.currency1.balanceOf(address(this)), prevBalance1 - 0.5 ether);

        hook.removeLiquidity(
            BaseCustomAccounting.RemoveLiquidityParams(
                hook.balanceOf(address(this)), 0, 0, MAX_DEADLINE, MIN_TICK, MAX_TICK, bytes32(0)
            )
        );

        liquidityTokenBal = hook.balanceOf(address(this));

        assertEq(liquidityTokenBal, 0);
        assertEq(key.currency0.balanceOf(address(this)), prevBalance0 - 0.25 ether);
        assertEq(key.currency1.balanceOf(address(this)), prevBalance1 - 0.25 ether);
    }
}
