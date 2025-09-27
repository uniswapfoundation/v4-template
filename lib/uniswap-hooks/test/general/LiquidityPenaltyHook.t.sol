// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {LiquidityPenaltyHook} from "src/general/LiquidityPenaltyHook.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {Position} from "v4-core/src/libraries/Position.sol";
import {FixedPoint128} from "v4-core/src/libraries/FixedPoint128.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {HookTest} from "test/utils/HookTest.sol";
import {toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {CustomRevert} from "v4-core/src/libraries/CustomRevert.sol";
import {BalanceDeltaAssertions} from "../utils/BalanceDeltaAssertions.sol";

contract LiquidityPenaltyHookTest is HookTest, BalanceDeltaAssertions {
    LiquidityPenaltyHook hook;
    PoolKey noHookKey;
    uint24 fee = 1000; // 0.1%

    address user = makeAddr("user"); // long term LP
    bytes32 bobSalt = keccak256(abi.encode(user));

    address attacker = makeAddr("attacker"); // JIT attacker
    bytes32 attackerSalt = keccak256(abi.encode(attacker));

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        hook = LiquidityPenaltyHook(
            address(
                uint160(
                    Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
                        | Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG | Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG
                )
            )
        );
        deployCodeTo("src/general/LiquidityPenaltyHook.sol:LiquidityPenaltyHook", abi.encode(manager, 1), address(hook));

        (key,) = initPool(currency0, currency1, IHooks(address(hook)), fee, SQRT_PRICE_1_1);
        (noHookKey,) = initPool(currency0, currency1, IHooks(address(0)), fee, SQRT_PRICE_1_1);

        vm.label(Currency.unwrap(currency0), "currency0");
        vm.label(Currency.unwrap(currency1), "currency1");
    }

    function test_deploy_LowOffset_reverts() public {
        vm.expectRevert();
        deployCodeTo("src/general/LiquidityPenaltyHook.sol:LiquidityPenaltyHook", abi.encode(manager, 0), address(hook));
    }

    function test_noSwaps() public {
        // add liquidity
        modifyPoolLiquidity(key, -600, 600, 1e18, 0);
        modifyPoolLiquidity(noHookKey, -600, 600, 1e18, 0);

        // remove liquidity
        BalanceDelta hookDelta = modifyPoolLiquidity(key, -600, 600, -1e17, 0);
        BalanceDelta noHookDelta = modifyPoolLiquidity(noHookKey, -600, 600, -1e17, 0);

        assertEq(hookDelta, noHookDelta, "No swaps: equivalent behavior");
    }

    function test_JIT_SingleLP() public {
        // add liquidity
        modifyPoolLiquidity(key, -600, 600, 1e18, 0);
        modifyPoolLiquidity(noHookKey, -600, 600, 1e18, 0);

        // swap
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true,
            amountSpecified: -1e15, //exact input
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });
        swapRouter.swap(key, swapParams, testSettings, "");
        swapRouter.swap(noHookKey, swapParams, testSettings, "");

        // calculate earned fees due to the swap
        BalanceDelta feeDelta =
            calculateFeeDelta(manager, key.toId(), address(modifyLiquidityRouter), -600, 600, bytes32(0));

        // remove liquidity during the same block (consolidate JIT attack), apply penalty
        vm.expectEmit(false, false, true, true);
        emit Donate(key.toId(), address(0), uint128(feeDelta.amount0()), uint128(feeDelta.amount1()));
        BalanceDelta hookDelta = modifyPoolLiquidity(key, -600, 600, -1e17, 0);

        // attacker removes liquidity in the unhooked pool without penalty
        BalanceDelta noHookDelta = modifyPoolLiquidity(noHookKey, -600, 600, -1e17, 0);

        assertEq(hookDelta, noHookDelta - feeDelta, "Hooked: JIT penalty applied");

        // since the ataccker is the only LP, himself is the recipient of the whole donation in the hooked pool
        BalanceDelta hookFeeDeltaAfterRemoval =
            calculateFeeDelta(manager, key.toId(), address(modifyLiquidityRouter), -600, 600, bytes32(0));
        assertAproxEqAbs(hookFeeDeltaAfterRemoval, feeDelta, 1, "Hooked: Attacker received donation");

        // in the unhooked pool, the attacker should have collected the fees during liquidity removal
        BalanceDelta noHookFeeDeltaAfterRemoval =
            calculateFeeDelta(manager, noHookKey.toId(), address(modifyLiquidityRouter), -600, 600, bytes32(0));
        assertEq(noHookFeeDeltaAfterRemoval, toBalanceDelta(0, 0), "Unhooked: Attacker collected fees");
    }

    function test_JIT_SingleLP_RemoveEntireLiquidity() public {
        // add liquidity
        modifyPoolLiquidity(key, -600, 600, 1e18, 0);
        modifyPoolLiquidity(noHookKey, -600, 600, 1e18, 0);

        // swap
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        SwapParams memory swapParams = SwapParams({
            zeroForOne: false,
            amountSpecified: -1e15, //exact input
            sqrtPriceLimitX96: MAX_PRICE_LIMIT
        });
        swapRouter.swap(key, swapParams, testSettings, "");
        swapRouter.swap(noHookKey, swapParams, testSettings, "");

        uint128 liquidityHookKey = StateLibrary.getLiquidity(manager, key.toId());
        uint128 liquidityNoHookKey = StateLibrary.getLiquidity(manager, noHookKey.toId());

        // remove entire liquidity
        BalanceDelta noHookDelta = modifyPoolLiquidity(noHookKey, -600, 600, -int128(liquidityNoHookKey), 0);

        // Can't withdraw all liquidity in the hooked since the attacker is the sole lp in range, and there
        // is no other active liquidity positions in range to receive the donation. Offset must be awaited.
        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(hook), // target address
                IHooks.afterRemoveLiquidity.selector, // function selector
                abi.encodeWithSelector(LiquidityPenaltyHook.NoLiquidityToReceiveDonation.selector), // reason
                abi.encodeWithSelector(Hooks.HookCallFailed.selector) // details
            )
        );
        BalanceDelta hookDelta = modifyPoolLiquidity(key, -600, 600, -int128(liquidityHookKey), 0);

        // advance block
        vm.roll(block.number + 1);

        // now the attacker can remove without penalty
        BalanceDelta hookDeltaAfterOffset = modifyPoolLiquidity(key, -600, 600, -int128(liquidityHookKey), 0);

        assertEq(hookDeltaAfterOffset, noHookDelta, "Hooked: penalty not applied after offset.");
    }

    function test_JIT_Swap() public {
        // add liquidity
        modifyPoolLiquidity(key, -600, 600, 1e18, bobSalt);
        modifyPoolLiquidity(key, -600, 600, 1e18, attackerSalt);
        modifyPoolLiquidity(noHookKey, -600, 600, 1e18, bobSalt);
        modifyPoolLiquidity(noHookKey, -600, 600, 1e18, attackerSalt);

        // swap
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true,
            amountSpecified: -1e15, //exact input
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });
        swapRouter.swap(key, swapParams, testSettings, "");
        swapRouter.swap(noHookKey, swapParams, testSettings, "");

        // calculate lp fees earned due to the swap
        BalanceDelta feeDelta =
            calculateFeeDelta(manager, key.toId(), address(modifyLiquidityRouter), -600, 600, bobSalt);

        // attacker removes the entire liquidity in the same block (consolidates JIT attack), penalty is applied.
        vm.expectEmit(false, false, true, true);
        emit Donate(key.toId(), address(0), uint128(feeDelta.amount0()), uint128(feeDelta.amount1()));
        BalanceDelta deltaHook = modifyPoolLiquidity(key, -600, 600, -1e18, attackerSalt);

        // attacker removes liquidity in the unhooked pool without penalty
        BalanceDelta deltaNoHook = modifyPoolLiquidity(noHookKey, -600, 600, -1e18, attackerSalt);

        assertEq(deltaHook, deltaNoHook - feeDelta, "Hooked: JIT penalty applied");

        // attacker's fees should be zero after removing liquidity
        BalanceDelta hookAttackerFeesAfterRemoval =
            calculateFeeDelta(manager, key.toId(), address(modifyLiquidityRouter), -600, 600, attackerSalt);
        assertEq(hookAttackerFeesAfterRemoval, toBalanceDelta(0, 0), "Hooked: Attacker's feeDelta zero");

        // user should have received the attacker's fees donation in the hooked pool
        BalanceDelta hookBobFeesAfterRemoval =
            calculateFeeDelta(manager, key.toId(), address(modifyLiquidityRouter), -600, 600, bobSalt);
        assertEq(hookBobFeesAfterRemoval, feeDelta + feeDelta, "user received attacker's fees");

        // advance block
        vm.roll(block.number + 1);

        // now user can remove without penalty in the hooked pool
        BalanceDelta hookDeltaBobAfterRemoval = modifyPoolLiquidity(key, -600, 600, -1e18, bobSalt);
        BalanceDelta noHookDeltaBobAfterRemoval = modifyPoolLiquidity(noHookKey, -600, 600, -1e18, bobSalt);

        assertEq(
            hookDeltaBobAfterRemoval,
            noHookDeltaBobAfterRemoval + feeDelta,
            "Hooked: user collects his and the attacker's fees"
        );
    }

    function test_JIT_addLiquidityFeeCollection() public {
        // add liquidity
        modifyPoolLiquidity(key, -600, 600, 1e18, bobSalt);
        modifyPoolLiquidity(key, -600, 600, 1e18, attackerSalt);
        modifyPoolLiquidity(noHookKey, -600, 600, 1e18, bobSalt);
        modifyPoolLiquidity(noHookKey, -600, 600, 1e18, attackerSalt);

        // swap
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true,
            amountSpecified: -1e15, //exact input
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });
        swapRouter.swap(key, swapParams, testSettings, "");
        swapRouter.swap(noHookKey, swapParams, testSettings, "");

        // calculate lp fees before adding liquidity
        BalanceDelta feeDelta =
            calculateFeeDelta(manager, key.toId(), address(modifyLiquidityRouter), -600, 600, bobSalt);

        // add a very small amount of liquidity (1e14 wei), which triggers fee collection
        BalanceDelta hookDeltaBobAddition = modifyPoolLiquidity(key, -600, 600, 1e14, bobSalt);
        BalanceDelta hookDeltaAttackerAddition = modifyPoolLiquidity(key, -600, 600, 1e14, attackerSalt);

        BalanceDelta noHookDeltaBobAddition = modifyPoolLiquidity(noHookKey, -600, 600, 1e14, bobSalt);
        BalanceDelta noHookDeltaAttackerAddition = modifyPoolLiquidity(noHookKey, -600, 600, 1e14, attackerSalt);

        // user and attacker collected fees on unhooked, but witheld in hook
        assertEq(hookDeltaBobAddition, noHookDeltaBobAddition - feeDelta, "unhooked collected, hooked witheld");
        assertEq(
            hookDeltaAttackerAddition, noHookDeltaAttackerAddition - feeDelta, "unhooked collected, hooked witheld"
        );

        // hook should hold ERC-6909 claims for both user and attacker's fees
        assertEq(
            manager.balanceOf(address(key.hooks), currency0.toId()),
            uint256(uint128(feeDelta.amount0())) * 2,
            "hook withheld fees for currency0 from user and attacker"
        );
        assertEq(
            manager.balanceOf(address(key.hooks), currency1.toId()),
            uint256(uint128(feeDelta.amount1())) * 2,
            "hook withheld fees for currency1 from user and attacker"
        );

        // now the attacker removes the entire liquidity position to consolidate JIT attack
        vm.expectEmit(false, false, true, true);
        emit Donate(key.toId(), address(0), uint128(feeDelta.amount0()), uint128(feeDelta.amount1()));
        BalanceDelta deltaHookAttackerRemoval = modifyPoolLiquidity(key, -600, 600, -(1e18 + 1e14), attackerSalt);

        // the hook should have burned the attacker ERC-6909 claims as donation
        assertEq(
            manager.balanceOf(address(key.hooks), currency0.toId()),
            uint256(uint128(feeDelta.amount0())),
            "hook burned attacker's claims"
        );
        assertEq(
            manager.balanceOf(address(key.hooks), currency1.toId()),
            uint256(uint128(feeDelta.amount1())),
            "hook burned attacker's claims"
        );

        // advance block
        vm.roll(block.number + 1);

        // user can now remove without penalty after the offset
        BalanceDelta hookDeltaBobRemoval = modifyPoolLiquidity(key, -600, 600, -1e14, bobSalt);
        BalanceDelta noHookDeltaBobRemoval = modifyPoolLiquidity(noHookKey, -600, 600, -1e14, bobSalt);

        assertAproxEqAbs(
            hookDeltaBobRemoval,
            noHookDeltaBobRemoval + feeDelta + feeDelta,
            1,
            "Hooked: user collects his and the attacker's fees"
        );
    }

    function test_JIT_MultipleSwaps() public {
        // add liquidity
        modifyPoolLiquidity(key, -600, 600, 1e18, bobSalt);
        modifyPoolLiquidity(key, -600, 600, 1e18, attackerSalt);
        modifyPoolLiquidity(noHookKey, -600, 600, 1e18, bobSalt);
        modifyPoolLiquidity(noHookKey, -600, 600, 1e18, attackerSalt);

        // swap with all possible combinations of zeroForOne and amountSpecified
        swapAllCombinations(key, 1e15);
        swapAllCombinations(noHookKey, 1e15);

        BalanceDelta feeDelta =
            calculateFeeDelta(manager, key.toId(), address(modifyLiquidityRouter), -600, 600, bobSalt);

        // attacker removes liquidity
        BalanceDelta deltaHook = modifyPoolLiquidity(key, -600, 600, -1e18, attackerSalt);
        BalanceDelta deltaNoHook = modifyPoolLiquidity(noHookKey, -600, 600, -1e18, attackerSalt);

        BalanceDelta hookFeesAttackerAfterRemoval =
            calculateFeeDelta(manager, key.toId(), address(modifyLiquidityRouter), -600, 600, attackerSalt);
        assertEq(hookFeesAttackerAfterRemoval, toBalanceDelta(0, 0), "Attacker's fees got penalized");

        BalanceDelta hookFeesBobAfterRemoval =
            calculateFeeDelta(manager, key.toId(), address(modifyLiquidityRouter), -600, 600, bobSalt);
        assertEq(hookFeesBobAfterRemoval, feeDelta + feeDelta, "user received attacker's fees");

        // advance block
        vm.roll(block.number + 1);

        // now user can remove without penalty in the hooked pool
        BalanceDelta hookDeltaBobAfterRemoval = modifyPoolLiquidity(key, -600, 600, -1e18, bobSalt);
        BalanceDelta noHookDeltaBobAfterRemoval = modifyPoolLiquidity(noHookKey, -600, 600, -1e18, bobSalt);

        assertEq(
            hookDeltaBobAfterRemoval,
            noHookDeltaBobAfterRemoval + feeDelta,
            "Hooked: user collects his and the attacker's fees"
        );
    }

    function test_donation_JIT() public {
        modifyPoolLiquidity(key, -600, 600, 1e18, 0);
        modifyPoolLiquidity(noHookKey, -600, 600, 1e18, 0);

        donateRouter.donate(key, 100000, 100000, "");
        donateRouter.donate(noHookKey, 100000, 100000, "");

        BalanceDelta feeDelta =
            calculateFeeDelta(manager, key.toId(), address(modifyLiquidityRouter), -600, 600, bytes32(0));

        BalanceDelta deltaHook = modifyPoolLiquidity(key, -600, 600, -1e17, 0);
        BalanceDelta deltaNoHook = modifyPoolLiquidity(noHookKey, -600, 600, -1e17, 0);

        assertEq(deltaHook, deltaNoHook - feeDelta, "applied penalty over donation JIT");
    }

    function test_donation_RemoveNextBlock() public {
        modifyPoolLiquidity(key, -600, 600, 1e18, 0);
        modifyPoolLiquidity(noHookKey, -600, 600, 1e18, 0);

        donateRouter.donate(key, 100000, 100000, "");
        donateRouter.donate(noHookKey, 100000, 100000, "");

        vm.roll(block.number + 1);

        // now can be removed without penalty
        BalanceDelta deltaHook = modifyPoolLiquidity(key, -600, 600, -1e17, 0);
        BalanceDelta deltaNoHook = modifyPoolLiquidity(noHookKey, -600, 600, -1e17, 0);

        assertEq(deltaHook, deltaNoHook, "removed liquidity without penalty");
    }

    function testFuzz_BlockNumberOffset_JIT(uint24 offset, uint24 removeBlockQuantity) public {
        vm.assume(offset > 1);
        vm.assume(removeBlockQuantity < offset);

        LiquidityPenaltyHook newHook = LiquidityPenaltyHook(
            address(
                uint160(
                    Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
                        | Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG | Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG
                ) + 2 ** 96
            ) // 2**96 is an offset to avoid collision with the hook address already in the test
        );

        deployCodeTo(
            "src/general/LiquidityPenaltyHook.sol:LiquidityPenaltyHook", abi.encode(manager, offset), address(newHook)
        );

        (PoolKey memory poolKey,) = initPool(currency0, currency1, IHooks(address(newHook)), fee, SQRT_PRICE_1_1);

        // add liquidity
        modifyPoolLiquidity(poolKey, -600, 600, 1e18, 0);
        modifyPoolLiquidity(noHookKey, -600, 600, 1e18, 0);

        // swap
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        SwapParams memory swapParams = SwapParams({
            zeroForOne: true,
            amountSpecified: -1e15, //exact input
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });
        swapRouter.swap(poolKey, swapParams, testSettings, "");
        swapRouter.swap(noHookKey, swapParams, testSettings, "");

        (int128 feesExpected0, int128 feesExpected1) =
            calculateFees(manager, noHookKey.toId(), address(modifyLiquidityRouter), -600, 600, bytes32(0));

        int128 feeDonation0 =
            SafeCast.toInt128(FullMath.mulDiv(SafeCast.toUint128(feesExpected0), offset - removeBlockQuantity, offset));
        int128 feeDonation1 =
            SafeCast.toInt128(FullMath.mulDiv(SafeCast.toUint128(feesExpected1), offset - removeBlockQuantity, offset));

        // remove liquidity
        vm.roll(block.number + removeBlockQuantity);
        BalanceDelta deltaHook = modifyPoolLiquidity(poolKey, -600, 600, -1e17, 0);
        BalanceDelta deltaNoHook = modifyPoolLiquidity(noHookKey, -600, 600, -1e17, 0);

        assertEq(BalanceDeltaLibrary.amount0(deltaHook), BalanceDeltaLibrary.amount0(deltaNoHook) - feeDonation0);
        assertEq(BalanceDeltaLibrary.amount1(deltaHook), BalanceDeltaLibrary.amount1(deltaNoHook) - feeDonation1);
    }

    function testFuzz_BlockNumberOffset_RemoveAfterSwap(uint24 offset, uint24 removeBlockQuantity) public {
        vm.assume(offset > 1);
        vm.assume(removeBlockQuantity > offset);

        LiquidityPenaltyHook newHook = LiquidityPenaltyHook(
            address(
                uint160(
                    Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
                        | Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG | Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG
                ) + 2 ** 96
            ) // 2**96 is an offset to avoid collision with the hook address already in the test
        );

        deployCodeTo(
            "src/general/LiquidityPenaltyHook.sol:LiquidityPenaltyHook", abi.encode(manager, offset), address(newHook)
        );

        (PoolKey memory poolKey,) = initPool(currency0, currency1, IHooks(address(newHook)), fee, SQRT_PRICE_1_1);

        // add liquidity
        modifyPoolLiquidity(poolKey, -600, 600, 1e18, 0);
        modifyPoolLiquidity(noHookKey, -600, 600, 1e18, 0);

        // swap
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        SwapParams memory swapParams = SwapParams({
            zeroForOne: true,
            amountSpecified: -1e15, //exact input
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });

        swapRouter.swap(poolKey, swapParams, testSettings, "");
        swapRouter.swap(noHookKey, swapParams, testSettings, "");

        vm.roll(block.number + removeBlockQuantity);
        BalanceDelta deltaHook = modifyPoolLiquidity(poolKey, -600, 600, -1e17, 0);
        BalanceDelta deltaNoHook = modifyPoolLiquidity(noHookKey, -600, 600, -1e17, 0);

        assertEq(BalanceDeltaLibrary.amount0(deltaHook), BalanceDeltaLibrary.amount0(deltaNoHook));
        assertEq(BalanceDeltaLibrary.amount1(deltaHook), BalanceDeltaLibrary.amount1(deltaNoHook));
    }

    function test_JIT_MultiplePools() public {
        // Validates that the hook correctly supports multiple pools at the same time
        (PoolKey memory poolKeyWithHook1,) = initPool(currency0, currency1, IHooks(address(hook)), 3000, SQRT_PRICE_1_2);
        (PoolKey memory poolKeyWithHook2,) = initPool(currency0, currency1, IHooks(address(hook)), 5000, SQRT_PRICE_2_1);

        (PoolKey memory poolKeyWithoutHook1,) = initPool(currency0, currency1, IHooks(address(0)), 3000, SQRT_PRICE_1_2);
        (PoolKey memory poolKeyWithoutHook2,) = initPool(currency0, currency1, IHooks(address(0)), 5000, SQRT_PRICE_2_1);

        // add liquidity to both pools
        modifyPoolLiquidity(poolKeyWithHook1, -600, 600, 1e18, 0);
        modifyPoolLiquidity(poolKeyWithHook2, -600, 600, 1e18, 0);

        modifyPoolLiquidity(poolKeyWithoutHook1, -600, 600, 1e18, 0);
        modifyPoolLiquidity(poolKeyWithoutHook2, -600, 600, 1e18, 0);

        // swap in both pools
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        SwapParams memory swapParams = SwapParams({
            zeroForOne: true,
            amountSpecified: -1e15, //exact input
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });

        swapRouter.swap(poolKeyWithHook1, swapParams, testSettings, "");
        swapRouter.swap(poolKeyWithHook2, swapParams, testSettings, "");

        swapRouter.swap(poolKeyWithoutHook1, swapParams, testSettings, "");
        swapRouter.swap(poolKeyWithoutHook2, swapParams, testSettings, "");

        // calculate fees
        BalanceDelta noHookFeesKey1 = calculateFeeDelta(
            manager, poolKeyWithoutHook1.toId(), address(modifyLiquidityRouter), -600, 600, bytes32(0)
        );
        BalanceDelta noHookFeesKey2 = calculateFeeDelta(
            manager, poolKeyWithoutHook2.toId(), address(modifyLiquidityRouter), -600, 600, bytes32(0)
        );

        // remove liquidity from both pools
        BalanceDelta deltaHook1 = modifyPoolLiquidity(poolKeyWithHook1, -600, 600, -1e17, 0);
        BalanceDelta deltaHook2 = modifyPoolLiquidity(poolKeyWithHook2, -600, 600, -1e17, 0);

        BalanceDelta deltaNoHook1 = modifyPoolLiquidity(poolKeyWithoutHook1, -600, 600, -1e17, 0);
        BalanceDelta deltaNoHook2 = modifyPoolLiquidity(poolKeyWithoutHook2, -600, 600, -1e17, 0);

        // penalties are applied
        assertEq(deltaHook1, deltaNoHook1 - noHookFeesKey1, "applied penalty over JIT");
        assertEq(deltaHook2, deltaNoHook2 - noHookFeesKey2, "applied penalty over JIT");
    }
}
