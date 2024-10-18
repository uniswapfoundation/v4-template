// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {Constants} from "v4-core/test/utils/Constants.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {ExampleHook} from "./ExampleHook.sol";

import "forge-std/console2.sol";

contract ExampleHookTest is Test, Deployers {
    using SafeCast for *;

    // TODO: Initialize this test with your hook. You will pass in your hook implementation before each test to set this.
    address hook;
    address user = address(0xBEEF);

    function setUp() public {
        initializeManagerRoutersAndPoolsWithLiq(IHooks(address(0)));
    }

    function test_exampleHook_beforeSwap() public {
        // TODO: This is where you pass in your hook's implementation.
        address impl = address(new ExampleHook(manager));
        _setUpBeforeSwapHook(impl);

        _setApprovalsFor(user, address(Currency.unwrap(key.currency0)));
        _setApprovalsFor(user, address(Currency.unwrap(key.currency1)));

        // Seeds liquidity into the hook.
        key.currency0.transfer(address(hook), 10e18);
        key.currency1.transfer(address(hook), 10e18);

        // Seeds liquidity into the user.

        key.currency0.transfer(address(user), 10e18);
        key.currency1.transfer(address(user), 10e18);

        // Seed liquidity into the user.

        uint256 userBalanceBefore0 = currency0.balanceOf(address(user));
        uint256 userBalanceBefore1 = currency1.balanceOf(address(user));

        uint256 hookBalanceBefore0 = currency0.balanceOf(address(hook));
        uint256 hookBalanceBefore1 = currency1.balanceOf(address(hook));

        // TODO: Change swap amount. Note: Remember that if a hook is taking from the pool based on this amount, the pool must have at least this amount of liquidity.
        uint256 amountToSwap = 1e6;

        // TODO: Change depending on what kind of swap you want.
        // Setting this value to true means currency0 is supplied.
        // Setting this value to false means currency1 is supplied.
        bool zeroForOne = false;

        // TODO: Set the sign of this value.
        // A negative amount means it is an exactInput swap, so the user is sending exactly that amount into the pool.
        // A positive amount means it is an exactOutput swap, so the user is only requesting that amount out of the swap.
        int256 amountSpecified = int256(amountToSwap);

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            // Note: if zeroForOne is true, the price is pushed down, otherwise its pushed up.
            sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
        });

        _printTestType(params.zeroForOne, params.amountSpecified);

        console2.log("--- STARTING BALANCES ---");

        console2.log("User balance in currency0 before swapping: ", userBalanceBefore0);
        console2.log("User balance in currency1 before swapping: ", userBalanceBefore1);
        console2.log("Hook balance in currency0 before swapping: ", hookBalanceBefore0);
        console2.log("Hook balance in currency1 before swapping: ", hookBalanceBefore1);

        vm.prank(user);
        swapRouter.swap(key, params, _defaultTestSettings(), ZERO_BYTES);

        uint256 userBalanceAfter0 = currency0.balanceOf(address(user));
        uint256 userBalanceAfter1 = currency1.balanceOf(address(user));

        uint256 hookBalanceAfter0 = currency0.balanceOf(address(hook));
        uint256 hookBalanceAfter1 = currency1.balanceOf(address(hook));

        console2.log("--- ENDING BALANCES ---");

        console2.log("User balance in currency0 after swapping: ", userBalanceAfter0);
        console2.log("User balance in currency1 after swapping: ", userBalanceAfter1);
        console2.log("Hook balance in currency0 after swapping: ", hookBalanceAfter0);
        console2.log("Hook balance in currency1 after swapping: ", hookBalanceAfter1);

        if (zeroForOne) {
            assertEq(userBalanceAfter0, userBalanceBefore0 - amountToSwap, "amount 0");
            assertEq(userBalanceAfter1, userBalanceBefore1 + amountToSwap, "amount 1");
        } else {
            assertEq(userBalanceAfter0, userBalanceBefore0 + amountToSwap, "amount 0");
            assertEq(userBalanceAfter1, userBalanceBefore1 - amountToSwap, "amount 1");
        }
    }

    /// INTERNAL HELPER FUNCTIONS ///

    function _printTestType(bool zeroForOne, int256 amountSpecified) internal {
        console2.log("--- TEST TYPE ---");
        string memory zeroForOneString = zeroForOne ? "zeroForOne" : "oneForZero";
        string memory swapType = amountSpecified < 0 ? "exactInput" : "exactOutput";
        string memory currencyRequiredFromUser = zeroForOne ? "currency0" : "currency1";
        string memory currencySpecified = zeroForOne == amountSpecified < 0 ? "currency0" : "currency1";

        console2.log("This is a", zeroForOneString, swapType, "swap");
        console2.log("The user will owe an amount in", currencyRequiredFromUser);
        console2.log("The currency specified is", currencySpecified);
    }

    function _setUpBeforeSwapHook(address impl) internal {
        address hookAddr = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        _etchHookAndInitPool(hookAddr, impl);
    }

    function _etchHookAndInitPool(address hookAddr, address implAddr) internal {
        vm.etch(hookAddr, implAddr.code);
        hook = hookAddr;
        (key,) = initPoolAndAddLiquidity(currency0, currency1, IHooks(hook), 100, SQRT_PRICE_1_1);
    }

    function _defaultTestSettings() internal returns (PoolSwapTest.TestSettings memory testSetting) {
        return PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
    }

    function _setApprovalsFor(address _user, address token) internal {
        address[8] memory toApprove = [
            address(swapRouter),
            address(swapRouterNoChecks),
            address(modifyLiquidityRouter),
            address(modifyLiquidityNoChecks),
            address(donateRouter),
            address(takeRouter),
            address(claimsRouter),
            address(nestedActionRouter.executor())
        ];

        for (uint256 i = 0; i < toApprove.length; i++) {
            vm.prank(_user);
            MockERC20(token).approve(toApprove[i], Constants.MAX_UINT256);
        }
    }
}
