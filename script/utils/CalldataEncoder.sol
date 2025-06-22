// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

/// @dev Provides functions to abi encode calldata for V4 interactions.
library CalldataEncoder {
    /// @dev Encodes the 'actions' and 'params' arguments for modifyLiquidity
    function encodeModifyLiquidityParams(
        PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        address recipient,
        uint256 amount0Max,
        uint256 amount1Max,
        bytes memory hookData
    ) internal pure returns (bytes memory actions, bytes[] memory params) {
        actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR), uint8(Actions.SWEEP), uint8(Actions.SWEEP)
        );

        params = new bytes[](4);
        params[0] = abi.encode(poolKey, tickLower, tickUpper, liquidity, amount0Max, amount1Max, recipient, hookData);
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
        params[2] = abi.encode(poolKey.currency0, recipient);
        params[3] = abi.encode(poolKey.currency1, recipient);
    }

    /// @dev Encodes the data for a multicall to create a pool AND add liquidity
    function encodeCreateAndMintMulticall(
        IPositionManager positionManager,
        PoolKey memory poolKey,
        uint160 startingPrice,
        bytes memory actions,
        bytes[] memory mintParams,
        uint256 deadline,
        bytes memory hookData
    ) internal pure returns (bytes[] memory params) {
        params = new bytes[](2);
        params[0] = abi.encodeWithSelector(positionManager.initializePool.selector, poolKey, startingPrice, hookData);
        params[1] = abi.encodeWithSelector(
            positionManager.modifyLiquidities.selector, abi.encode(actions, mintParams), deadline
        );
    }
}
