// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MyCustomCurve} from "./MyCustomCurve.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";

/// @title FiftyFifty: the Gambling Hook
/// @notice 50% of the time you 1.5x your money, 50% of the time you lose half of it
contract FiftyFifty is MyCustomCurve {
    constructor(IPoolManager _poolManager) MyCustomCurve(_poolManager) {}

    function _getUnspecifiedAmount(PoolKey calldata, bool, bool exactInput, uint256 specifiedAmount)
        internal
        view
        override
        returns (uint256 unspecifiedAmount)
    {
        // TODO: use a better RNG
        uint256 pseudoRandom = uint256(keccak256(abi.encodePacked(block.number, block.timestamp, block.prevrandao)));

        bool win = pseudoRandom % 2 == 0;
        if (exactInput && win) {
            // for wins on exact input, the output (unspecified) is 1.5 the input
            unspecifiedAmount = (specifiedAmount * 3) / 2;
        } else if (exactInput && !win) {
            // for losses on exact input, the output (unspecified) is half the input
            unspecifiedAmount = specifiedAmount / 2;
        } else if (!exactInput && win) {
            // for wins on exact output, the input (unspecified) is half the output
            unspecifiedAmount = specifiedAmount / 2;
        } else {
            // for losses on exact output, the input (unspecified) is the output
            unspecifiedAmount = specifiedAmount * 2;
        }
    }

    /// @dev UNSAFE FOR PRODUCTION, DOES NOT ACCOUNT FOR OWNERSHIP
    /// @dev a minimal but unsafe example of adding liquidity to the hook
    function addLiquidity(PoolKey calldata key, uint256 amountEach) external returns (BalanceDelta amountsAdded) {
        // from the function parameters, determine how much of each token to add
        // for the sake of example, the user specifies the same amount of each token
        amountsAdded = _getAmountsAddLiquidity(amountEach);

        require(amountsAdded.amount0() <= 0, "FiftyFifty: amount0 must be negative when adding liquidity");
        require(amountsAdded.amount1() <= 0, "FiftyFifty: amount1 must be negative when adding liquidity");

        // transfers ERC20 to PoolManager so the Hook can mint ERC6909
        _addOrRemove(key.currency0, key.currency1, amountsAdded, msg.sender);
    }

    /// @dev UNSAFE FOR PRODUCTION, DOES NOT CHECK FOR PERMISSIONS
    /// @dev a minimal but unsafe example of removing liquidity from the hook
    function removeLiquidity(PoolKey calldata key, uint256 amountEach) external returns (BalanceDelta amountsRemoved) {
        // from the function parameters, determine how much of each token to remove
        // for the sake of example, the user specifies the same amount of each token
        amountsRemoved = _getAmountsRemoveLiquidity(amountEach);

        require(amountsRemoved.amount0() >= 0, "FiftyFifty: amount0 must be positive when removing liquidity");
        require(amountsRemoved.amount1() >= 0, "FiftyFifty: amount1 must be positive when removing liquidity");

        // burns ERC6909 to transfer ERC20 to the user
        _addOrRemove(key.currency0, key.currency1, amountsRemoved, msg.sender);
    }

    /// @dev an example liquidity-add calculation
    /// in theory this function can take different parameters to determine the amount (and ratio) of assets to add
    function _getAmountsAddLiquidity(uint256 amountEach) internal pure returns (BalanceDelta amountsToAdd) {
        // not production ready: UNSAFE CASTING
        amountsToAdd = toBalanceDelta(-int128(int256(amountEach)), -int128(int256(amountEach)));
    }

    /// @dev an example liquidity-remove calculation
    /// in theory this function can take different parameters to determine the amount (and ratio) of assets to remove
    function _getAmountsRemoveLiquidity(uint256 amountEach) internal pure returns (BalanceDelta amountsToRemove) {
        // not production ready: UNSAFE CASTING
        amountsToRemove = toBalanceDelta(int128(int256(amountEach)), int128(int256(amountEach)));
    }
}
