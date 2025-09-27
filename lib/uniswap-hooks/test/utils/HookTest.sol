// SPDX-License-Identifier: MIT
// OpenZeppelin Uniswap Hooks (last updated v1.1.0) (test/utils/HookTest.sol)
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {BalanceDelta, toBalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {Position} from "v4-core/src/libraries/Position.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {FixedPoint128} from "v4-core/src/libraries/FixedPoint128.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {IHookEvents} from "src/interfaces/IHookEvents.sol";
import {IPoolManagerEvents} from "test/utils/interfaces/IPoolManagerEvents.sol";

// @dev Set of utilities to test Hooks.
contract HookTest is Test, Deployers, IPoolManagerEvents, IHookEvents {
    // @dev Calculate the current `feesAccrued` for a given position.
    function calculateFees(
        IPoolManager manager,
        PoolId poolId,
        address owner,
        int24 tickLower,
        int24 tickUpper,
        bytes32 salt
    ) internal view returns (int128, int128) {
        bytes32 positionKey = Position.calculatePositionKey(owner, tickLower, tickUpper, salt);
        (uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128) =
            StateLibrary.getPositionInfo(manager, poolId, positionKey);

        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) =
            StateLibrary.getFeeGrowthInside(manager, poolId, tickLower, tickUpper);

        uint256 fees0 = FullMath.mulDiv(feeGrowthInside0X128 - feeGrowthInside0LastX128, liquidity, FixedPoint128.Q128);
        uint256 fees1 = FullMath.mulDiv(feeGrowthInside1X128 - feeGrowthInside1LastX128, liquidity, FixedPoint128.Q128);

        return (int128(int256(fees0)), int128(int256(fees1)));
    }

    // @dev Calculate the current feeDelta for a given position.
    function calculateFeeDelta(
        IPoolManager manager,
        PoolId poolId,
        address owner,
        int24 tickLower,
        int24 tickUpper,
        bytes32 salt
    ) internal view returns (BalanceDelta feeDelta) {
        (int128 fees0, int128 fees1) = calculateFees(manager, poolId, owner, tickLower, tickUpper, salt);
        return toBalanceDelta(fees0, fees1);
    }

    // @dev Modify the liquidity of a given position.
    function modifyPoolLiquidity(
        PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper,
        int256 liquidity,
        bytes32 salt
    ) internal returns (BalanceDelta) {
        ModifyLiquidityParams memory modifyLiquidityParams =
            ModifyLiquidityParams({tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: liquidity, salt: salt});
        return modifyLiquidityRouter.modifyLiquidity(poolKey, modifyLiquidityParams, "");
    }

    // @dev Swaps all combinations of `zeroForOne` (true/false) and `amountSpecified` (+,-) in a given pool.
    function swapAllCombinations(PoolKey memory poolKey, uint256 amount) internal {
        for (uint256 i = 0; i < 4; i++) {
            swap(poolKey, i < 2 ? false : true, i % 2 == 0 ? -int256(amount) : int256(amount), ZERO_BYTES);
        }
    }
}
