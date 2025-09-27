// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {BaseDynamicFeeMock} from "test/mocks/BaseDynamicFeeMock.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {ProtocolFeeLibrary} from "v4-core/src/libraries/ProtocolFeeLibrary.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {Pool} from "v4-core/src/libraries/Pool.sol";
import {BaseDynamicFee} from "src/fee/BaseDynamicFee.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {CustomRevert} from "v4-core/src/libraries/CustomRevert.sol";

contract BaseDynamicFeeTest is Test, Deployers {
    using StateLibrary for IPoolManager;
    using ProtocolFeeLibrary for uint16;

    BaseDynamicFeeMock dynamicFeesHooks;

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

    function setUp() public {
        deployFreshManagerAndRouters();

        dynamicFeesHooks = BaseDynamicFeeMock(address(uint160(Hooks.AFTER_INITIALIZE_FLAG)));
        deployCodeTo(
            "test/mocks/BaseDynamicFeeMock.sol:BaseDynamicFeeMock", abi.encode(manager), address(dynamicFeesHooks)
        );

        deployMintAndApprove2Currencies();
        (key,) = initPoolAndAddLiquidity(
            currency0, currency1, IHooks(address(dynamicFeesHooks)), LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1
        );

        vm.label(Currency.unwrap(currency0), "currency0");
        vm.label(Currency.unwrap(currency1), "currency1");
    }

    function test_setFee_afterInitializeFeeTooLarge_reverts() public {
        key.tickSpacing = 30;
        uint24 fee = 1000001;
        dynamicFeesHooks.setFee(fee);

        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(dynamicFeesHooks),
                IHooks.afterInitialize.selector,
                abi.encodeWithSelector(LPFeeLibrary.LPFeeTooLarge.selector, fee),
                abi.encodeWithSelector(Hooks.HookCallFailed.selector)
            )
        );
        manager.initialize(key, SQRT_PRICE_1_1);
    }

    function test_setFee_afterInitialize_succeeds() public {
        key.tickSpacing = 30;
        dynamicFeesHooks.setFee(123);

        manager.initialize(key, SQRT_PRICE_1_1);
        assertEq(_fetchPoolLPFee(key), 123);
    }

    function test_updateDynamicLPFee_callerNotHook_reverts() public {
        vm.expectRevert(IPoolManager.UnauthorizedDynamicLPFeeUpdate.selector);
        manager.updateDynamicLPFee(key, 123);
    }

    function test_setFee_poolHasStaticFee_reverts() public {
        key.fee = 3000; // static fee
        dynamicFeesHooks.setFee(123);

        // afterInitialize will try to update the fee, and fail
        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(dynamicFeesHooks),
                IHooks.afterInitialize.selector,
                abi.encodeWithSelector(BaseDynamicFee.NotDynamicFee.selector),
                abi.encodeWithSelector(Hooks.HookCallFailed.selector)
            )
        );
        manager.initialize(key, SQRT_PRICE_1_1);
    }

    function test_setFee_feeTooLarge_reverts() public {
        assertEq(_fetchPoolLPFee(key), 0);

        uint24 fee = 1000001;
        dynamicFeesHooks.setFee(1000001);

        vm.expectRevert(abi.encodeWithSelector(LPFeeLibrary.LPFeeTooLarge.selector, fee));
        dynamicFeesHooks.poke(key);
    }

    function test_setFee_poke_succeeds() public {
        assertEq(_fetchPoolLPFee(key), 0);

        dynamicFeesHooks.setFee(123);
        dynamicFeesHooks.poke(key);

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), -100, 98, 79228162514264329749955861424, 1e18, -1, 123);

        swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);

        assertEq(_fetchPoolLPFee(key), 123);
    }

    function test_swap_100PercentLPFeeExactInput_succeeds() public {
        assertEq(_fetchPoolLPFee(key), 0);

        dynamicFeesHooks.setFee(1000000);
        dynamicFeesHooks.poke(key);
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), -100, 0, SQRT_PRICE_1_1, 1e18, -1, 1000000);

        swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);

        assertEq(_fetchPoolLPFee(key), 1000000);
    }

    function test_swap_50PercentLPFeeExactInput_succeeds() public {
        assertEq(_fetchPoolLPFee(key), 0);

        dynamicFeesHooks.setFee(500000);
        dynamicFeesHooks.poke(key);
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), -100, 49, 79228162514264333632135824623, 1e18, -1, 500000);

        swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);

        assertEq(_fetchPoolLPFee(key), 500000);
    }

    function test_swap_50PercentLPFeeExactOutput_succeeds() public {
        assertEq(_fetchPoolLPFee(key), 0);

        dynamicFeesHooks.setFee(500000);
        dynamicFeesHooks.poke(key);

        SwapParams memory params =
            SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_PRICE_1_2});
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), -202, 100, 79228162514264329670727698909, 1e18, -1, 500000);

        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        assertEq(_fetchPoolLPFee(key), 500000);
    }

    function test_swap_feeIsMax_reverts() public {
        assertEq(_fetchPoolLPFee(key), 0);

        dynamicFeesHooks.setFee(1000000);
        dynamicFeesHooks.poke(key);

        SwapParams memory params =
            SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_PRICE_1_2});
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.expectRevert(Pool.InvalidFeeForExactOut.selector);
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
    }

    function test_swap_99PercentFeeExactOutput_succeeds() public {
        assertEq(_fetchPoolLPFee(key), 0);

        dynamicFeesHooks.setFee(999999);
        dynamicFeesHooks.poke(key);

        vm.prank(feeController);
        manager.setProtocolFee(key, 1000);

        SwapParams memory params =
            SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_PRICE_1_2});
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.expectRevert(Pool.InvalidFeeForExactOut.selector);
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
    }

    function test_swap_100PercentFeeExactInputWithProtocol_succeeds() public {
        assertEq(_fetchPoolLPFee(key), 0);

        dynamicFeesHooks.setFee(1000000);
        dynamicFeesHooks.poke(key);
        vm.prank(feeController);
        manager.setProtocolFee(key, 1000);

        SwapParams memory params =
            SwapParams({zeroForOne: true, amountSpecified: -1000, sqrtPriceLimitX96: SQRT_PRICE_1_2});
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), -1000, 0, SQRT_PRICE_1_1, 1e18, -1, 1000000);

        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        uint256 expectedProtocolFee = (uint256(-params.amountSpecified) * 1000) / 1e6;
        assertEq(manager.protocolFeesAccrued(currency0), expectedProtocolFee);
    }

    function test_swap_emitsSwapFee_succeeds() public {
        assertEq(_fetchPoolLPFee(key), 0);

        dynamicFeesHooks.setFee(123);
        dynamicFeesHooks.poke(key);

        vm.prank(feeController);
        manager.setProtocolFee(key, 1000);

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), -100, 98, 79228162514264329749955861424, 1e18, -1, 1123);

        swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);

        assertEq(_fetchPoolLPFee(key), 123);
    }

    function test_swap_fuzz_succeeds(
        bool zeroForOne,
        uint24 lpFee,
        uint16 protocolFee0,
        uint16 protocolFee1,
        int256 amountSpecified
    ) public {
        assertEq(_fetchPoolLPFee(key), 0);

        lpFee = uint16(bound(lpFee, 0, 1000000));
        protocolFee0 = uint16(bound(protocolFee0, 0, 1000));
        protocolFee1 = uint16(bound(protocolFee1, 0, 1000));
        vm.assume(amountSpecified != 0);

        uint24 protocolFee = (uint24(protocolFee1) << 12) | uint24(protocolFee0);
        dynamicFeesHooks.setFee(lpFee);
        dynamicFeesHooks.poke(key);

        vm.prank(feeController);
        manager.setProtocolFee(key, protocolFee);

        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
        });
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        BalanceDelta delta = swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        uint24 swapFee = uint16(protocolFee).calculateSwapFee(lpFee);

        uint256 expectedProtocolFee;
        if (zeroForOne) {
            expectedProtocolFee = (uint256(uint128(-delta.amount0())) * protocolFee0) / 1e6;

            if (lpFee == 0) {
                assertEq(protocolFee0, swapFee);
                if (((uint256(uint128(-delta.amount0())) * protocolFee0) % 1e6) != 0) expectedProtocolFee++;
            }

            assertEq(manager.protocolFeesAccrued(currency0), expectedProtocolFee);
        } else {
            expectedProtocolFee = (uint256(uint128(-delta.amount1())) * protocolFee1) / 1e6;

            if (lpFee == 0) {
                assertEq(protocolFee0, swapFee);
                if (((uint256(uint128(-delta.amount1())) * protocolFee1) % 1e6) != 0) expectedProtocolFee++;
            }

            assertEq(manager.protocolFeesAccrued(currency1), expectedProtocolFee);
        }
    }

    function _fetchPoolLPFee(PoolKey memory _key) internal view returns (uint256 lpFee) {
        PoolId id = _key.toId();
        (,,, lpFee) = manager.getSlot0(id);
    }
}
