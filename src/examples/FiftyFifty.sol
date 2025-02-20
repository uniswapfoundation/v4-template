// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseCustomCurve} from "uniswap-hooks/base/BaseCustomCurve.sol";
import {BaseCustomAccounting} from "uniswap-hooks/base/BaseCustomAccounting.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";

/// @title FiftyFifty: the Gambling Hook
/// @notice 50% of the time you double your money, 50% of the time you lose it all
contract FiftyFifty is BaseCustomCurve {
    constructor(IPoolManager _poolManager) BaseCustomCurve(_poolManager) {}

    function _getUnspecifiedAmount(IPoolManager.SwapParams calldata params)
        internal
        view
        override
        returns (uint256 unspecifiedAmount)
    {
        bool exactInput = params.amountSpecified < 0;
        uint256 swapAmount = exactInput ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);

        // TODO: use a better RNG
        uint256 pseudoRandom = uint256(keccak256(abi.encodePacked(block.number, block.timestamp, block.prevrandao)));

        bool win = pseudoRandom % 2 == 0;
        if (win && exactInput) {
            return swapAmount * 2;
        } else if (win && !exactInput) {
            // for wins on exact output, the input (unspecified) is half the output
            return swapAmount / 2;
        } else {
            return 0;
        }
    }

    function _mint(BaseCustomCurve.AddLiquidityParams memory params, BalanceDelta callerDelta, BalanceDelta feesAccrued, uint256 shares)
        internal
        override
    {}
    function _burn(BaseCustomCurve.RemoveLiquidityParams memory params, BalanceDelta callerDelta, BalanceDelta feesAccrued, uint256 shares)
        internal
        override
    {}
    function _getAmountIn(BaseCustomCurve.AddLiquidityParams memory params)
        internal
        override
        returns (uint256 amount0, uint256 amount1, uint256 shares)
    {}
    function _getAmountOut(BaseCustomCurve.RemoveLiquidityParams memory params)
        internal
        override
        returns (uint256 amount0, uint256 amount1, uint256 shares)
    {}
}
