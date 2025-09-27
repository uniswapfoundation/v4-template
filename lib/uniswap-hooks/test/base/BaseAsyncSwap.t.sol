// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {BaseAsyncSwapMock} from "test/mocks/BaseAsyncSwapMock.sol";
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
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";

contract BaseAsyncSwapTest is Test, Deployers {
    using StateLibrary for IPoolManager;
    using ProtocolFeeLibrary for uint16;

    BaseAsyncSwapMock hook;

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

        hook = BaseAsyncSwapMock(address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG)));
        deployCodeTo("test/mocks/BaseAsyncSwapMock.sol:BaseAsyncSwapMock", abi.encode(manager), address(hook));

        deployMintAndApprove2Currencies();
        (key,) = initPoolAndAddLiquidity(
            currency0, currency1, IHooks(address(hook)), LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1
        );

        vm.label(Currency.unwrap(currency0), "currency0");
        vm.label(Currency.unwrap(currency1), "currency1");
    }

    function test_swap_exactInput_succeeds() public {
        SwapParams memory swapParams =
            SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_PRICE_1_2});
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        uint256 balance0Before = currency0.balanceOfSelf();
        uint256 balance1Before = currency1.balanceOfSelf();

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), 0, 0, 79228162514264337593543950336, 1e18, 0, 0);

        swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);

        uint256 balance0After = currency0.balanceOfSelf();
        uint256 balance1After = currency1.balanceOfSelf();

        assertEq(balance0Before - balance0After, 100);
        assertEq(balance1Before, balance1After);
    }

    function test_swap_exactOutput_succeeds() public {
        SwapParams memory swapParams =
            SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_PRICE_1_2});
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        uint256 balance0Before = currency0.balanceOfSelf();
        uint256 balance1Before = currency1.balanceOfSelf();

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), -101, 100, 79228162514264329670727698909, 1e18, -1, 0);

        swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);

        uint256 balance0After = currency0.balanceOfSelf();
        uint256 balance1After = currency1.balanceOfSelf();

        // async swaps are not applied to exact-output swaps
        assertEq(balance0Before - balance0After, 101);
        assertEq(balance1After - balance1Before, 100);
    }

    function test_swap_exactInput_notZeroForOne_succeeds() public {
        SwapParams memory swapParams =
            SwapParams({zeroForOne: false, amountSpecified: -100, sqrtPriceLimitX96: SQRT_PRICE_1_2});
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        uint256 balance0Before = currency0.balanceOfSelf();
        uint256 balance1Before = currency1.balanceOfSelf();

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), 0, 0, 79228162514264337593543950336, 1e18, 0, 0);

        swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);

        uint256 balance0After = currency0.balanceOfSelf();
        uint256 balance1After = currency1.balanceOfSelf();

        assertEq(balance1Before - balance1After, 100);
        assertEq(balance0Before, balance0After);
    }

    function test_swap_exactOutput_notZeroForOne_succeeds() public {
        SwapParams memory swapParams =
            SwapParams({zeroForOne: false, amountSpecified: 100, sqrtPriceLimitX96: MAX_PRICE_LIMIT});
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        uint256 balance0Before = currency0.balanceOfSelf();
        uint256 balance1Before = currency1.balanceOfSelf();

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), 100, -101, 79228162514264345516360201763, 1e18, 0, 0);

        swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);

        uint256 balance0After = currency0.balanceOfSelf();
        uint256 balance1After = currency1.balanceOfSelf();

        assertEq(balance1Before - balance1After, 101);
        assertEq(balance0After - balance0Before, 100);
    }

    function test_swap_fuzz_succeeds(bool zeroForOne, int120 amountSpecified) public {
        vm.assume(amountSpecified != 0);

        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
        });
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        BalanceDelta delta = swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        if (amountSpecified < 0 && zeroForOne) {
            assertEq(delta.amount0(), amountSpecified);
            assertEq(delta.amount1(), 0);
        } else if (amountSpecified < 0 && !zeroForOne) {
            assertEq(delta.amount0(), 0);
            assertEq(delta.amount1(), amountSpecified);
        } else if (amountSpecified > 0 && zeroForOne) {
            assertTrue(delta.amount0() < 0);
            assertTrue(delta.amount1() > 0);
        } else {
            assertTrue(delta.amount0() > 0);
            assertTrue(delta.amount1() < 0);
        }
    }
}
