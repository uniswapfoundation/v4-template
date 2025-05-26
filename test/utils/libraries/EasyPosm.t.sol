// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

import {EasyPosm} from "./EasyPosm.sol";

import {Deployers} from "../Deployers.sol";

contract EasyPosmTest is Test, Deployers {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Currency currency0;
    Currency currency1;

    int24 tickLower;
    int24 tickUpper;

    PoolKey key;
    PoolKey nativeKey;

    function setUp() public {
        deployArtifacts();

        (currency0, currency1) = deployCurrencyPair();

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(address(0)));
        nativeKey = PoolKey(Currency.wrap(address(0)), currency1, 3000, 60, IHooks(address(0)));

        poolManager.initialize(key, Constants.SQRT_PRICE_1_1);
        poolManager.initialize(nativeKey, Constants.SQRT_PRICE_1_1);

        // full-range liquidity
        tickLower = TickMath.minUsableTick(key.tickSpacing);
        tickUpper = TickMath.maxUsableTick(key.tickSpacing);
    }

    function test_mintLiquidity() public {
        uint256 liquidityToMint = 100e18;
        address recipient = address(this);

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            uint128(liquidityToMint)
        );

        (, BalanceDelta delta) = positionManager.mint(
            key,
            tickLower,
            tickUpper,
            liquidityToMint,
            type(uint256).max,
            type(uint256).max,
            recipient,
            block.timestamp + 1,
            Constants.ZERO_BYTES
        );
        assertEq(delta.amount0(), -int128(uint128(amount0 + 1 wei)));
        assertEq(delta.amount1(), -int128(uint128(amount1 + 1 wei)));
    }

    function test_mintLiquidityNative() public {
        uint256 liquidityToMint = 100e18;
        address recipient = address(this);

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            uint128(liquidityToMint)
        );

        vm.deal(address(this), amount0 + 1);
        (, BalanceDelta delta) = positionManager.mint(
            nativeKey,
            tickLower,
            tickUpper,
            liquidityToMint,
            amount0 + 1,
            amount1 + 1,
            recipient,
            block.timestamp + 1,
            Constants.ZERO_BYTES
        );
        assertEq(delta.amount0(), -int128(uint128(amount0 + 1 wei)));
        assertEq(delta.amount1(), -int128(uint128(amount1 + 1 wei)));
    }

    function test_increaseLiquidity() public {
        (uint256 tokenId,) = positionManager.mint(
            key,
            tickLower,
            tickUpper,
            100e18,
            type(uint256).max,
            type(uint256).max,
            address(this),
            block.timestamp + 1,
            Constants.ZERO_BYTES
        );

        uint256 liquidityToAdd = 1e18;

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            uint128(liquidityToAdd)
        );

        BalanceDelta delta = positionManager.increaseLiquidity(
            tokenId, liquidityToAdd, type(uint256).max, type(uint256).max, block.timestamp + 1, Constants.ZERO_BYTES
        );
        assertEq(delta.amount0(), -int128(uint128(amount0 + 1 wei)));
        assertEq(delta.amount1(), -int128(uint128(amount1 + 1 wei)));
    }

    function test_increaseLiquidityNative() public {
        uint256 liquidityToMint = 100e18;
        address recipient = address(this);

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            uint128(liquidityToMint)
        );

        vm.deal(address(this), amount0 + 1);
        (uint256 tokenId, BalanceDelta delta) = positionManager.mint(
            nativeKey,
            tickLower,
            tickUpper,
            liquidityToMint,
            amount0 + 1,
            amount1 + 1,
            recipient,
            block.timestamp + 1,
            Constants.ZERO_BYTES
        );

        uint256 liquidityToIncrease = 1e18;

        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            uint128(liquidityToIncrease)
        );

        vm.deal(address(this), amount0 + 1);
        delta = positionManager.increaseLiquidity(
            tokenId, liquidityToIncrease, amount0 + 1, amount1 + 1, block.timestamp + 1, Constants.ZERO_BYTES
        );
        assertEq(delta.amount0(), -int128(uint128(amount0 + 1 wei)));
        assertEq(delta.amount1(), -int128(uint128(amount1 + 1 wei)));
    }

    function test_decreaseLiquidity() public {
        (uint256 tokenId,) = positionManager.mint(
            key,
            tickLower,
            tickUpper,
            100e18,
            type(uint256).max,
            type(uint256).max,
            address(this),
            block.timestamp + 1,
            Constants.ZERO_BYTES
        );

        uint256 liquidityToRemove = 1e18;

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            uint128(liquidityToRemove)
        );

        BalanceDelta delta = positionManager.decreaseLiquidity(
            tokenId, liquidityToRemove, 0, 0, address(this), block.timestamp + 1, Constants.ZERO_BYTES
        );
        assertEq(delta.amount0(), int128(uint128(amount0)));
        assertEq(delta.amount1(), int128(uint128(amount1)));
    }

    function test_burn() public {
        (uint256 tokenId, BalanceDelta mintDelta) = positionManager.mint(
            key,
            tickLower,
            tickUpper,
            100e18,
            type(uint256).max,
            type(uint256).max,
            address(this),
            block.timestamp + 1,
            Constants.ZERO_BYTES
        );

        BalanceDelta delta =
            positionManager.burn(tokenId, 0, 0, address(this), block.timestamp + 1, Constants.ZERO_BYTES);
        assertEq(delta.amount0(), -mintDelta.amount0() - 1 wei);
        assertEq(delta.amount1(), -mintDelta.amount1() - 1 wei);
    }

    // This test requires a donateRouter, TODO
    // function test_collect() public {
    //     (uint256 tokenId,) = positionManager.mint(
    //         key,
    //         tickLower,
    //         tickUpper,
    //         100e18,
    //         type(uint256).max,
    //         type(uint256).max,
    //         address(this),
    //         block.timestamp + 1,
    //         Constants.ZERO_BYTES
    //     );

    //     // donate to regenerate fee revenue
    //     uint128 feeRevenue0 = 1e18;
    //     uint128 feeRevenue1 = 0.1e18;

    //     poolManager.donate(key, feeRevenue0, feeRevenue1, Constants.ZERO_BYTES);

    //     // position collects half of the revenue since 50% of the liquidity is minted in setUp()
    //     BalanceDelta delta =
    //         positionManager.collect(tokenId, 0, 0, address(0x123), block.timestamp + 1, Constants.ZERO_BYTES);
    //     assertEq(uint128(delta.amount0()), feeRevenue0 - 1 wei);
    //     assertEq(uint128(delta.amount1()), feeRevenue1 - 1 wei);
    // }
}
