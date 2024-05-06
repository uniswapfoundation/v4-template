// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {CurrencySettleTake} from "v4-core/src/libraries/CurrencySettleTake.sol";
import {CustomCurveBase} from "../CustomCurveBase.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract CSMM is CustomCurveBase {
    using CurrencySettleTake for Currency;

    struct CallbackData {
        Currency currency0;
        Currency currency1;
        uint256 amountEach;
    }

    constructor(IPoolManager _poolManager) CustomCurveBase(_poolManager) {}

    function getAmountIn(PoolKey calldata, IPoolManager.SwapParams calldata params, bytes calldata)
        internal
        pure
        override
        returns (uint256)
    {
        int256 amountSpecified = params.amountSpecified;
        return 0 < amountSpecified ? uint256(amountSpecified) : uint256(-amountSpecified);
    }

    function getAmountOut(PoolKey calldata, IPoolManager.SwapParams calldata params, bytes calldata)
        internal
        pure
        override
        returns (uint256)
    {
        int256 amountSpecified = params.amountSpecified;
        return 0 < amountSpecified ? uint256(amountSpecified) : uint256(-amountSpecified);
    }

    function addLiquidity(PoolKey calldata key, bytes calldata hookData) internal override {
        uint256 amountEach = abi.decode(hookData, (uint256));
        poolManager.unlock(abi.encode(CallbackData(key.currency0, key.currency1, amountEach)));
    }

    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        CallbackData memory params = abi.decode(data, (CallbackData));
        uint256 amountEach = params.amountEach;
        Currency currency0 = params.currency0;
        Currency currency1 = params.currency1;
        currency0.take(poolManager, address(this), amountEach, true);
        currency1.take(poolManager, address(this), amountEach, true);
        currency0.settle(poolManager, msg.sender, amountEach, false);
        currency1.settle(poolManager, msg.sender, amountEach, false);

        return new bytes(0);
    }
}
