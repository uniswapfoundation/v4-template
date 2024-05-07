// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "./forks/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {CurrencySettleTake} from "v4-core/src/libraries/CurrencySettleTake.sol";
import {console2} from "forge-std/console2.sol";

abstract contract CustomCurveBase is BaseHook {
    using PoolIdLibrary for PoolKey;
    using CurrencySettleTake for Currency;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getAmountIn(PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata hookData)
        internal
        virtual
        returns (uint256)
    {}

    function getAmountOut(PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata hookData)
        internal
        virtual
        returns (uint256)
    {}

    function addLiquidity(PoolKey calldata key, bytes calldata hookData) external virtual {}

    // --- Hook Functions --- //

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata hookData)
        external
        override
        returns (bytes4, int128)
    {
        uint256 amountIn = getAmountIn(key, params, hookData);
        uint256 amountOut = getAmountOut(key, params, hookData);

        int128 hookDelta = params.amountSpecified < 0 ? int128(int256(amountIn)) : -int128(int256(amountIn));

        // zeroForOne: swapper pays currency0 for currency1
        // take amountIn: creating a debt, paid for by swapper
        // settle amountOut: create a credit, claimed by swapper
        if (params.zeroForOne) {
            key.currency0.take(poolManager, address(this), amountIn, true);
            key.currency1.settle(poolManager, address(this), amountOut, true);
        } else {
            key.currency1.take(poolManager, address(this), amountIn, true);
            key.currency0.settle(poolManager, address(this), amountOut, true);
        }

        assembly {
            tstore(0, amountOut)
        }
        return (BaseHook.beforeSwap.selector, hookDelta);
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        int256 amountOut;
        assembly {
            amountOut := tload(0)
        }
        int128 hookDelta = params.amountSpecified < 0 ? -int128(amountOut) : int128(amountOut);
        return (BaseHook.afterSwap.selector, hookDelta);
    }

    function beforeAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external override returns (bytes4) {
        revert("CustomCurveBase: add liquidity with addLiquidity()");
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
}
