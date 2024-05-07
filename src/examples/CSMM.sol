// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {CurrencySettleTake} from "v4-core/src/libraries/CurrencySettleTake.sol";
import {CustomCurveBase} from "../CustomCurveBase.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {console2} from "forge-std/console2.sol";

contract CSMM is CustomCurveBase {
    using CurrencySettleTake for Currency;

    struct CallbackData {
        uint256 amountEach;
        Currency currency0;
        Currency currency1;
        address sender;
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

    function addLiquidity(PoolKey calldata key, bytes calldata hookData) external override {
        uint256 amountEach = abi.decode(hookData, (uint256));
        poolManager.unlock(abi.encode(CallbackData(amountEach, key.currency0, key.currency1, msg.sender)));
    }

    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        CallbackData memory params = abi.decode(data, (CallbackData));

        params.currency0.take(poolManager, address(this), params.amountEach, true);
        params.currency1.take(poolManager, address(this), params.amountEach, true);
        params.currency0.settle(poolManager, params.sender, params.amountEach, false);
        params.currency1.settle(poolManager, params.sender, params.amountEach, false);

        return new bytes(0);
    }
}
