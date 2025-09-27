// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {BaseDynamicFeeMock} from "../mocks/BaseDynamicFeeMock.sol";
import {AntiSandwichMock} from "../mocks/AntiSandwichMock.sol";
import {HookTest} from "../utils/HookTest.sol";
import {toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BalanceDeltaAssertions} from "../utils/BalanceDeltaAssertions.sol";

contract AntiSandwichHookTest is HookTest, BalanceDeltaAssertions {
    AntiSandwichMock hook;
    PoolKey noHookKey;

    BaseDynamicFeeMock dynamicFeesHooks;

    // @dev expected values for pools with 1e18 liquidity.
    int128 constant SWAP_AMOUNT_1e15 = 1e15;
    int128 constant SWAP_RESULT_1e15 = 999000999000999;

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        hook = AntiSandwichMock(
            address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG))
        );
        deployCodeTo("test/mocks/AntiSandwichMock.sol:AntiSandwichMock", abi.encode(manager), address(hook));

        dynamicFeesHooks = BaseDynamicFeeMock(address(uint160(Hooks.AFTER_INITIALIZE_FLAG)));
        deployCodeTo(
            "test/mocks/BaseDynamicFeeMock.sol:BaseDynamicFeeMock", abi.encode(manager), address(dynamicFeesHooks)
        );

        (key,) = initPoolAndAddLiquidity(
            currency0, currency1, IHooks(address(hook)), LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1
        );
        (noHookKey,) = initPoolAndAddLiquidity(
            currency0, currency1, IHooks(address(dynamicFeesHooks)), LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1
        );

        vm.label(Currency.unwrap(currency0), "currency0");
        vm.label(Currency.unwrap(currency1), "currency1");
    }

    /// @notice Unit test for a single swap, not zero for one.
    function test_swap_single_notZeroForOne() public {
        BalanceDelta swapDelta = swap(key, false, -SWAP_AMOUNT_1e15, ZERO_BYTES);
        assertEq(swapDelta, toBalanceDelta(SWAP_RESULT_1e15, -SWAP_AMOUNT_1e15));
    }

    /// @notice Unit test for a single swap, zero for one.
    function test_swap_single_zeroForOne() public {
        BalanceDelta swapDelta = swap(key, true, -SWAP_AMOUNT_1e15, ZERO_BYTES);
        assertEq(swapDelta, toBalanceDelta(-SWAP_AMOUNT_1e15, SWAP_RESULT_1e15));
    }

    function test_swap_zeroForOne_FrontrunExactInput_BackrunExactInput() public {
        // front run, exactInput
        // - sends token0 (SWAP_AMOUNT)
        // - receives token1 (unknown amount)
        BalanceDelta deltaAttack1WithKey = swap(key, true, -SWAP_AMOUNT_1e15, ZERO_BYTES);
        BalanceDelta deltaAttack1WithoutKey = swap(noHookKey, true, -SWAP_AMOUNT_1e15, ZERO_BYTES);

        assertTrue(
            deltaAttack1WithKey == deltaAttack1WithoutKey,
            "both pools should give the same output for the first block swap"
        );

        // user swap
        BalanceDelta deltaUserWithKey = swap(key, true, -SWAP_AMOUNT_1e15, ZERO_BYTES);
        BalanceDelta deltaUserWithoutKey = swap(noHookKey, true, -SWAP_AMOUNT_1e15, ZERO_BYTES);

        assertTrue(deltaUserWithKey == deltaUserWithoutKey, "both pools should give the same output");

        // back run, exactInput
        // - sends token1 (amount received in front run)
        // - receives token0 (unknown amount)
        // To make a profit, the ataccker must receive more token0 than he sent in the frontrun.
        BalanceDelta deltaAttack2WithKey = swap(key, false, -int256(deltaAttack1WithKey.amount1()), ZERO_BYTES);
        BalanceDelta deltaAttack2WithoutKey = swap(noHookKey, false, -int256(deltaAttack1WithKey.amount1()), ZERO_BYTES);

        // If the attacker receives equal or less token0 than he sent in the frontrun, he loses money.
        assertLe(
            deltaAttack2WithKey.amount0(),
            -deltaAttack1WithKey.amount0(),
            "attacker should lose money in the hooked pool"
        );

        assertGt(
            deltaAttack2WithoutKey.amount0(),
            -deltaAttack1WithoutKey.amount0(),
            "attacker should make a profit in the unhooked pool"
        );

        // next block
        vm.roll(block.number + 1);

        BalanceDelta deltaResetWithKey = swap(key, false, -SWAP_AMOUNT_1e15, ZERO_BYTES);
        BalanceDelta deltaResetWithoutKey = swap(noHookKey, false, -SWAP_AMOUNT_1e15, ZERO_BYTES);

        assertEq(deltaResetWithKey.amount0(), deltaResetWithoutKey.amount0(), "hook should reset state");
    }

    function test_swap_zeroForOne_FrontrunExactInput_BackrunExactOutput() public {
        // front run, exactInput
        // - sends token0 (SWAP_AMOUNT)
        // - receives token1 (unknown amount)
        BalanceDelta deltaAttack1WithKey = swap(key, true, -SWAP_AMOUNT_1e15, ZERO_BYTES);
        BalanceDelta deltaAttack1WithoutKey = swap(noHookKey, true, -SWAP_AMOUNT_1e15, ZERO_BYTES);

        assertTrue(
            deltaAttack1WithKey == deltaAttack1WithoutKey,
            "both pools should give the same output for the first block swap"
        );

        // user swap
        BalanceDelta deltaUserWithKey = swap(key, true, -SWAP_AMOUNT_1e15, ZERO_BYTES);
        BalanceDelta deltaUserWithoutKey = swap(noHookKey, true, -SWAP_AMOUNT_1e15, ZERO_BYTES);

        assertTrue(deltaUserWithKey == deltaUserWithoutKey, "both pools should give the same output");

        // back run, exactOutput
        // - sends token1 (unknown amount)
        // - receives token0 (amount sent in front run)
        // To make a profit, the attacker must send less token1 than he received in the frontrun.
        BalanceDelta deltaAttack2WithKey = swap(key, false, -int256(deltaAttack1WithKey.amount0()), ZERO_BYTES);
        BalanceDelta deltaAttack2WithoutKey = swap(noHookKey, false, -int256(deltaAttack1WithKey.amount0()), ZERO_BYTES);

        // If the attacker sends more or equal token1 than he received in the frontrun, he loses money.
        assertGe(
            -deltaAttack2WithKey.amount1(),
            deltaAttack1WithKey.amount1(),
            "attacker should lose money in the hooked pool"
        );

        assertLt(
            -deltaAttack2WithoutKey.amount1(),
            deltaAttack1WithoutKey.amount1(),
            "attacker should make a profit in the unhooked pool"
        );

        // next block
        vm.roll(block.number + 1);

        BalanceDelta deltaResetWithKey = swap(key, false, -SWAP_AMOUNT_1e15, ZERO_BYTES);
        BalanceDelta deltaResetWithoutKey = swap(noHookKey, false, -SWAP_AMOUNT_1e15, ZERO_BYTES);

        assertEq(deltaResetWithKey.amount0(), deltaResetWithoutKey.amount0(), "hook should reset state");
    }

    function test_swap_zeroForOne_FrontrunExactOutput_BackrunExactInput() public {
        // front run, exactOutput
        // - gives token0 (unknown amount)
        // - receives token1 (SWAP_AMOUNT)
        BalanceDelta deltaAttack1WithKey = swap(key, true, SWAP_AMOUNT_1e15, ZERO_BYTES);
        BalanceDelta deltaAttack1WithoutKey = swap(noHookKey, true, SWAP_AMOUNT_1e15, ZERO_BYTES);

        assertTrue(
            deltaAttack1WithKey == deltaAttack1WithoutKey,
            "both pools should give the same output for the first block swap"
        );

        // user swap
        BalanceDelta deltaUserWithKey = swap(key, true, SWAP_AMOUNT_1e15, ZERO_BYTES);
        BalanceDelta deltaUserWithoutKey = swap(noHookKey, true, SWAP_AMOUNT_1e15, ZERO_BYTES);

        assertTrue(deltaUserWithKey == deltaUserWithoutKey, "both pools should give the same output");

        // back run, exactInput
        // - gives token1 (amount received in front run)
        // - receives token0 (unknown amount)
        // To make a profit, the attacker must receive more token0 than he sent in the frontrun.
        BalanceDelta deltaAttack2WithKey = swap(key, false, int256(-deltaAttack1WithKey.amount1()), ZERO_BYTES);
        BalanceDelta deltaAttack2WithoutKey = swap(noHookKey, false, int256(-deltaAttack1WithKey.amount1()), ZERO_BYTES);

        // If the attacker receives equal or less token0 than he sent in the frontrun, he loses money.
        assertLe(
            deltaAttack2WithKey.amount0(),
            -deltaAttack1WithKey.amount0(),
            "attacker should lose money in the hooked pool"
        );

        assertGt(
            deltaAttack2WithoutKey.amount0(),
            -deltaAttack1WithoutKey.amount0(),
            "attacker should make a profit in the unhooked pool"
        );

        // next block
        vm.roll(block.number + 1);

        BalanceDelta deltaResetWithKey = swap(key, false, -SWAP_AMOUNT_1e15, ZERO_BYTES);
        BalanceDelta deltaResetWithoutKey = swap(noHookKey, false, -SWAP_AMOUNT_1e15, ZERO_BYTES);

        assertEq(deltaResetWithKey.amount0(), deltaResetWithoutKey.amount0(), "hook should reset state");
    }

    function test_swap_zeroForOne_FrontrunExactOutput_BackrunExactOutput() public {
        // front run, exactOutput
        // - sends token0 (unknown amount)
        // - receives token1 (SWAP_AMOUNT)
        BalanceDelta deltaAttack1WithKey = swap(key, true, SWAP_AMOUNT_1e15, ZERO_BYTES);
        BalanceDelta deltaAttack1WithoutKey = swap(noHookKey, true, SWAP_AMOUNT_1e15, ZERO_BYTES);

        assertTrue(
            deltaAttack1WithKey == deltaAttack1WithoutKey,
            "both pools should give the same output for the first block swap"
        );

        // user swap
        BalanceDelta deltaUserWithKey = swap(key, true, SWAP_AMOUNT_1e15, ZERO_BYTES);
        BalanceDelta deltaUserWithoutKey = swap(noHookKey, true, SWAP_AMOUNT_1e15, ZERO_BYTES);

        assertTrue(deltaUserWithKey == deltaUserWithoutKey, "both pools should give the same output");

        // back run, exactOutput
        // - sends token1 (unknown amount)
        // - receives token0 (amount of token0 sent in front run)
        // To make a profit, the attacker must send less token1 than he received in the frontrun.
        BalanceDelta deltaAttack2WithKey = swap(key, false, -int256(deltaAttack1WithKey.amount0()), ZERO_BYTES);
        BalanceDelta deltaAttack2WithoutKey = swap(noHookKey, false, -int256(deltaAttack1WithKey.amount0()), ZERO_BYTES);

        // If the attacker sends more or equal token1 than he received in the frontrun, he loses money.
        assertGe(
            -deltaAttack2WithKey.amount1(),
            deltaAttack1WithKey.amount1(),
            "attacker should lose money in the hooked pool"
        );

        assertLt(
            -deltaAttack2WithoutKey.amount1(),
            deltaAttack1WithoutKey.amount1(),
            "attacker should make a profit in the unhooked pool"
        );

        // next block
        vm.roll(block.number + 1);

        BalanceDelta deltaResetWithKey = swap(key, false, -SWAP_AMOUNT_1e15, ZERO_BYTES);
        BalanceDelta deltaResetWithoutKey = swap(noHookKey, false, -SWAP_AMOUNT_1e15, ZERO_BYTES);

        assertEq(deltaResetWithKey.amount0(), deltaResetWithoutKey.amount0(), "hook should reset state");
    }

    /// @notice Unit test for a failed sandwich attack using the hook.
    function test_swap_failedSandwich() public {
        // front run, first transaction
        BalanceDelta delta = swap(key, true, -SWAP_AMOUNT_1e15, ZERO_BYTES);

        // user swap
        swap(key, true, -SWAP_AMOUNT_1e15, ZERO_BYTES);

        // back run, second transaction
        BalanceDelta deltaEnd = swap(key, false, -int256(delta.amount1()), ZERO_BYTES);

        assertLe(deltaEnd.amount0(), -delta.amount0(), "front runner should lose money");
    }

    /// @notice Unit test for a successful sandwich attack without using the hook.
    function test_swap_successfulSandwich() public {
        // front run, first transaction
        BalanceDelta delta = swap(noHookKey, true, -SWAP_AMOUNT_1e15, ZERO_BYTES);

        // user swap
        swap(noHookKey, true, -SWAP_AMOUNT_1e15, ZERO_BYTES);

        // front run, second transaction
        BalanceDelta deltaEnd = swap(noHookKey, false, -int256(delta.amount1()), ZERO_BYTES);

        assertGe(deltaEnd.amount0(), -delta.amount0(), "front runner should make a profit");
    }

    /// @notice Unit test for a successful sandwich attack using the hook in the oneForZero direction.
    /// note: the hook doesn't provide protection in the oneForZero direction.
    function test_swap_successfulSandwich_oneForZero() public {
        // front run, first transaction
        BalanceDelta deltaHook = swap(key, false, -SWAP_AMOUNT_1e15, ZERO_BYTES);
        BalanceDelta deltaNoHook = swap(noHookKey, false, -SWAP_AMOUNT_1e15, ZERO_BYTES);

        assertEq(deltaHook, deltaNoHook, "both pools should give the same output");

        // user swap
        BalanceDelta deltaUserHook = swap(key, false, -SWAP_AMOUNT_1e15, ZERO_BYTES);
        BalanceDelta deltaUserNoHook = swap(noHookKey, false, -SWAP_AMOUNT_1e15, ZERO_BYTES);

        assertEq(deltaUserHook, deltaUserNoHook, "both pools should give the same output");

        // backrun, second transaction
        BalanceDelta deltaHookEnd = swap(key, true, -int256(deltaHook.amount0()), ZERO_BYTES);
        BalanceDelta deltaNoHookEnd = swap(noHookKey, true, -int256(deltaNoHook.amount0()), ZERO_BYTES);

        assertEq(deltaHookEnd, deltaNoHookEnd, "both pools should give the same output");

        assertGe(deltaHookEnd.amount1(), -deltaHook.amount1(), "front runner should make a profit");
        assertGe(deltaNoHookEnd.amount1(), -deltaNoHook.amount1(), "front runner should make a profit");
    }
}
