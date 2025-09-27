// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {BaseDynamicAfterFee} from "src/fee/BaseDynamicAfterFee.sol";
import {BaseDynamicAfterFeeMock} from "test/mocks/BaseDynamicAfterFeeMock.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {V4Quoter} from "v4-periphery/src/lens/V4Quoter.sol";
import {Deploy} from "v4-periphery/test/shared/Deploy.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {CustomRevert} from "v4-core/src/libraries/CustomRevert.sol";
import {HookTest} from "test/utils/HookTest.sol";
import {IV4Quoter} from "test/utils/interfaces/IV4Quoter.sol";

contract BaseDynamicAfterFeeTest is HookTest {
    using SafeCast for *;

    BaseDynamicAfterFeeMock dynamicFeesHook;
    IV4Quoter quoter;

    PoolKey unhookedKey;
    PoolKey nativeUnhookedKey;

    function setUp() public {
        deployFreshManagerAndRouters();

        dynamicFeesHook = BaseDynamicAfterFeeMock(
            payable(
                address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG))
            )
        );
        deployCodeTo(
            "test/mocks/BaseDynamicAfterFeeMock.sol:BaseDynamicAfterFeeMock",
            abi.encode(manager),
            address(dynamicFeesHook)
        );

        deployMintAndApprove2Currencies();

        (key,) = initPoolAndAddLiquidity(currency0, currency1, IHooks(address(dynamicFeesHook)), 1000, SQRT_PRICE_1_1);
        (unhookedKey,) = initPoolAndAddLiquidity(currency0, currency1, IHooks(address(0)), 1000, SQRT_PRICE_1_1);

        // deal(address(this), 10 ether);
        (nativeKey,) = initPoolAndAddLiquidityETH(
            CurrencyLibrary.ADDRESS_ZERO, currency1, IHooks(address(dynamicFeesHook)), 1000, SQRT_PRICE_1_1, 1 ether
        );
        (nativeUnhookedKey,) = initPoolAndAddLiquidityETH(
            CurrencyLibrary.ADDRESS_ZERO, currency1, IHooks(address(0)), 1000, SQRT_PRICE_1_1, 1 ether
        );

        vm.label(Currency.unwrap(currency0), "currency0");
        vm.label(Currency.unwrap(currency1), "currency1");
        vm.label(address(0), "native");

        quoter = IV4Quoter(address(Deploy.v4Quoter(address(manager), "")));
    }

    function test_swap_100PercentHookFee_ExactInput_succeeds() public {
        uint128 swapAmount = 100;
        // Since this is an exactInput swap, a target of 0 means that the user doesn't receive any output.
        uint256 target = 0;

        dynamicFeesHook.setMockTargetUnspecifiedAmount(target, true);

        // Simulate the swap quote in an unhooked pool.
        (uint256 unhookedQuote,) = quoter.quoteExactInputSingle(
            IV4Quoter.QuoteExactSingleParams({
                poolKey: unhookedKey,
                zeroForOne: true,
                exactAmount: swapAmount,
                hookData: ZERO_BYTES
            })
        );

        vm.expectEmit(true, true, true, true, address(dynamicFeesHook));
        emit HookFee(PoolId.unwrap(key.toId()), address(swapRouter), 0, unhookedQuote.toUint128());

        uint256 swapperCurrency1Before = currency1.balanceOf(address(this));

        swap(key, true, -int128(swapAmount), ZERO_BYTES);

        uint256 swapperCurrency1After = currency1.balanceOf(address(this));
        uint256 hookCurrency1After = currency1.balanceOf(address(dynamicFeesHook));

        assertEq(hookCurrency1After, unhookedQuote, "hook keeps 100%");
        assertEq(swapperCurrency1After, swapperCurrency1Before, "user gets 0%");
    }

    function test_swap_100PercentHookFee_ExactInput_Native_succeeds() public {
        uint128 swapAmount = 100;
        // Since this is an exactInput swap, a target of 0 means that the user doesn't receive any output.
        uint256 target = 0;

        dynamicFeesHook.setMockTargetUnspecifiedAmount(target, true);

        (uint256 unhookedNativeQuote,) = quoter.quoteExactInputSingle(
            IV4Quoter.QuoteExactSingleParams({
                poolKey: nativeUnhookedKey,
                zeroForOne: true,
                exactAmount: swapAmount,
                hookData: ZERO_BYTES
            })
        );

        vm.expectEmit(true, true, true, true, address(dynamicFeesHook));
        emit HookFee(PoolId.unwrap(nativeKey.toId()), address(swapRouter), 0, unhookedNativeQuote.toUint128());

        uint256 swapperCurrency1Before = currency1.balanceOf(address(this));

        swap(nativeKey, true, -int128(swapAmount), ZERO_BYTES);

        uint256 swapperCurrency1After = currency1.balanceOf(address(this));
        uint256 hookCurrency1After = currency1.balanceOf(address(dynamicFeesHook));

        assertEq(hookCurrency1After, unhookedNativeQuote, "hook keeps 100%");
        assertEq(swapperCurrency1After, swapperCurrency1Before, "user gets 0%");
    }

    function test_swap_50PercentHookFee_ExactInput_succeeds() public {
        uint128 swapAmount = 100;

        (uint256 unhookedQuote,) = quoter.quoteExactInputSingle(
            IV4Quoter.QuoteExactSingleParams({
                poolKey: unhookedKey,
                zeroForOne: true,
                exactAmount: swapAmount,
                hookData: ZERO_BYTES
            })
        );

        // Since this is an exactInput swap, a target of `unhookedQuote / 2` means that the user receives
        // 50% of the output.
        uint256 target = unhookedQuote / 2;
        uint256 fee = unhookedQuote - target;

        dynamicFeesHook.setMockTargetUnspecifiedAmount(target, true);

        vm.expectEmit(true, true, true, true, address(dynamicFeesHook));
        emit HookFee(PoolId.unwrap(key.toId()), address(swapRouter), 0, fee.toUint128());

        uint256 swapperCurrency1Before = currency1.balanceOf(address(this));
        uint256 swapperCurrency0Before = currency0.balanceOf(address(this));

        swap(key, true, -int128(swapAmount), ZERO_BYTES);

        uint256 swapperCurrency1After = currency1.balanceOf(address(this));
        uint256 swapperCurrency0After = currency0.balanceOf(address(this));
        uint256 hookCurrency1After = currency1.balanceOf(address(dynamicFeesHook));

        assertEq(swapperCurrency0After, swapperCurrency0Before - swapAmount, "user pays the exactInput");
        assertEq(swapperCurrency1After, swapperCurrency1Before + target, "user gets 50% of the output");
        assertEq(hookCurrency1After, fee, "hook keeps 50% of the output");
    }

    function test_swap_50PercentHookFee_ExactOutput_succeeds() public {
        uint128 swapAmount = 100;

        (uint256 unhookedQuote,) = quoter.quoteExactOutputSingle(
            IV4Quoter.QuoteExactSingleParams({
                poolKey: unhookedKey,
                zeroForOne: true,
                exactAmount: swapAmount,
                hookData: ZERO_BYTES
            })
        );

        // Since this is an exactOutput swap, a target of `unhookedQuote * 2` means that the user pays
        // double the input, effectively receiving 50% of what he ends up paying for.
        uint256 target = unhookedQuote * 2;
        uint256 fee = target - unhookedQuote;

        dynamicFeesHook.setMockTargetUnspecifiedAmount(target, true);

        vm.expectEmit(true, true, true, true, address(dynamicFeesHook));
        emit HookFee(PoolId.unwrap(key.toId()), address(swapRouter), fee.toUint128(), 0);

        uint256 swapperCurrency1Before = currency1.balanceOf(address(this));
        uint256 swapperCurrency0Before = currency0.balanceOf(address(this));

        swap(key, true, int128(swapAmount), ZERO_BYTES);

        uint256 swapperCurrency1After = currency1.balanceOf(address(this));
        uint256 swapperCurrency0After = currency0.balanceOf(address(this));
        uint256 hookCurrency0After = currency0.balanceOf(address(dynamicFeesHook));

        assertEq(swapperCurrency0After, swapperCurrency0Before - target, "user pays double the input");
        assertEq(swapperCurrency1After, swapperCurrency1Before + swapAmount, "user gets the exactOutput");
        assertEq(hookCurrency0After, fee, "hook keeps 50% of the input");
    }

    function test_swap_TargetExceeded_ExactInput_NoOp() public {
        uint128 swapAmount = 100;

        (uint256 unhookedQuote,) = quoter.quoteExactInputSingle(
            IV4Quoter.QuoteExactSingleParams({
                poolKey: unhookedKey,
                zeroForOne: true,
                exactAmount: swapAmount,
                hookData: ZERO_BYTES
            })
        );

        // Since this is an exactInput swap, and the target is larger than the natural output,
        // the hook will not take any fee and will act as a no-op.
        uint256 target = unhookedQuote * 2;

        dynamicFeesHook.setMockTargetUnspecifiedAmount(target, true);

        uint256 swapperCurrency1Before = currency1.balanceOf(address(this));
        uint256 swapperCurrency0Before = currency0.balanceOf(address(this));

        swap(key, true, -int128(swapAmount), ZERO_BYTES);

        uint256 swapperCurrency1After = currency1.balanceOf(address(this));
        uint256 swapperCurrency0After = currency0.balanceOf(address(this));
        uint256 hookCurrency1After = currency1.balanceOf(address(dynamicFeesHook));

        assertEq(hookCurrency1After, 0, "noOp:hook doesn't take any");
        assertEq(swapperCurrency0After, swapperCurrency0Before - swapAmount, "noOp: user pays normal input");
        assertEq(swapperCurrency1After, swapperCurrency1Before + unhookedQuote, "noOp: user gets normal output");
    }

    function test_swap_TargetExceeded_ExactOutput_NoOp() public {
        uint128 swapAmount = 100;

        (uint256 unhookedQuote,) = quoter.quoteExactOutputSingle(
            IV4Quoter.QuoteExactSingleParams({
                poolKey: unhookedKey,
                zeroForOne: true,
                exactAmount: swapAmount,
                hookData: ZERO_BYTES
            })
        );

        // Since this is an exactOutput swap, and the target is smaller than the natural output,
        // the hook will not take any fee and will act as a no-op.
        uint256 target = unhookedQuote / 2;

        dynamicFeesHook.setMockTargetUnspecifiedAmount(target, true);

        uint256 swapperCurrency1Before = currency1.balanceOf(address(this));
        uint256 swapperCurrency0Before = currency0.balanceOf(address(this));

        swap(key, true, int128(swapAmount), ZERO_BYTES);

        uint256 swapperCurrency1After = currency1.balanceOf(address(this));
        uint256 swapperCurrency0After = currency0.balanceOf(address(this));
        uint256 hookCurrency1After = currency1.balanceOf(address(dynamicFeesHook));

        assertEq(hookCurrency1After, 0, "noOp:hook doesn't take any");
        assertEq(swapperCurrency0After, swapperCurrency0Before - unhookedQuote, "noOp: user pays normal input");
        assertEq(swapperCurrency1After, swapperCurrency1Before + swapAmount, "noOp: user gets normal output");
    }

    //     // function test_swap_deltaExceeds_succeeds() public {
    //     //     dynamicFeesHook.setMockTargetUnspecifiedAmount(101, true);

    //     //     vm.expectRevert(
    //     //         abi.encodeWithSelector(
    //     //             CustomRevert.WrappedError.selector,
    //     //             address(dynamicFeesHook),
    //     //             IHooks.afterSwap.selector,
    //     //             abi.encodeWithSelector(BaseDynamicAfterFee.TargetOutputExceeds.selector),
    //     //             abi.encodeWithSelector(Hooks.HookCallFailed.selector)
    //     //         )
    //     //     );
    //     //     swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
    //     // }

    function test_swap_fuzz_ExactInput_succeeds(bool zeroForOne, uint24 hookFee, uint128 amountSpecified) public {
        hookFee = uint24(bound(hookFee, 0, 1e6));
        amountSpecified = uint128(bound(amountSpecified, 1, 6017734268818166));

        (uint256 unhookedQuote,) = quoter.quoteExactInputSingle(
            IV4Quoter.QuoteExactSingleParams({
                poolKey: unhookedKey,
                zeroForOne: zeroForOne,
                exactAmount: amountSpecified,
                hookData: ZERO_BYTES
            })
        );

        // deltaFee is (0-100%) of the unhookedQuote
        uint256 deltaFee = (unhookedQuote * hookFee) / 1e6;
        // Since this is exactInput, the target is maximun amount the user must receive.
        uint256 targetAmount = unhookedQuote - deltaFee;

        dynamicFeesHook.setMockTargetUnspecifiedAmount(targetAmount, true);
        BalanceDelta delta = swap(key, zeroForOne, -int128(amountSpecified), ZERO_BYTES);

        if (zeroForOne) {
            assertEq(delta.amount0(), -int128(amountSpecified));
            assertLe(delta.amount1(), targetAmount.toInt128());
        } else {
            assertLe(delta.amount0(), targetAmount.toInt128());
            assertEq(delta.amount1(), -int128(amountSpecified));
        }
    }

    function test_swap_fuzz_ExactOutput_succeeds(bool zeroForOne, uint24 hookFee, uint128 amountSpecified) public {
        hookFee = uint24(bound(hookFee, 0, 1e6));
        amountSpecified = uint128(bound(amountSpecified, 1, 5981737760509662));

        (uint256 unhookedQuote,) = quoter.quoteExactOutputSingle(
            IV4Quoter.QuoteExactSingleParams({
                poolKey: unhookedKey,
                zeroForOne: zeroForOne,
                exactAmount: amountSpecified,
                hookData: ZERO_BYTES
            })
        );

        // deltaFee is (0-100%) of the unhookedQuote
        uint256 deltaFee = (unhookedQuote * hookFee) / 1e6;
        // Since this is exactOutput, the target is the minimum amount the user must pay.
        // target is (100-200%) of the unhookedQuote
        uint256 targetAmount = unhookedQuote + deltaFee;

        dynamicFeesHook.setMockTargetUnspecifiedAmount(targetAmount, true);
        BalanceDelta delta = swap(key, zeroForOne, int128(amountSpecified), ZERO_BYTES);

        if (zeroForOne) {
            assertGe(delta.amount0(), -targetAmount.toInt128());
            assertEq(delta.amount1(), int128(amountSpecified));
        } else {
            assertEq(delta.amount0(), int128(amountSpecified));
            assertGe(delta.amount1(), -targetAmount.toInt128());
        }
    }
}
