// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IUniswapV4Router04} from "hookmate/interfaces/router/IUniswapV4Router04.sol";
import {AddressConstants} from "hookmate/constants/AddressConstants.sol";

/// @dev Determines dependent addresses necessary for liquidity operations.
///   The non-overloaded function call will revert if a new or not-known chain is used.
library LoadDependencies {
    function run()
        internal
        view
        returns (
            IPermit2 permit2,
            IPoolManager poolManager,
            IPositionManager positionManager,
            IUniswapV4Router04 swapRouter
        )
    {
        (permit2, poolManager, positionManager, swapRouter) = _loadDependencies(
            AddressConstants.getPermit2Address(),
            AddressConstants.getPoolManagerAddress(block.chainid),
            AddressConstants.getPositionManagerAddress(block.chainid),
            AddressConstants.getV4SwapRouterAddress(block.chainid)
        );
    }

    /// @dev Use this in the event we're using a chain which is not publicly known/supported.
    function run(
        address permit2Address,
        address poolManagerAddress,
        address positionManagerAddress,
        address swapRouterAddress
    )
        internal
        pure
        returns (
            IPermit2 permit2,
            IPoolManager poolManager,
            IPositionManager positionManager,
            IUniswapV4Router04 swapRouter
        )
    {
        (permit2, poolManager, positionManager, swapRouter) =
            _loadDependencies(permit2Address, poolManagerAddress, positionManagerAddress, swapRouterAddress);
    }

    /// @dev Core logic
    function _loadDependencies(
        address permit2Address,
        address poolManagerAddress,
        address positionManagerAddress,
        address swapRouterAddress
    )
        internal
        pure
        returns (
            IPermit2 permit2,
            IPoolManager poolManager,
            IPositionManager positionManager,
            IUniswapV4Router04 swapRouter
        )
    {
        permit2 = IPermit2(permit2Address);
        poolManager = IPoolManager(poolManagerAddress);
        positionManager = IPositionManager(positionManagerAddress);
        swapRouter = IUniswapV4Router04(payable(swapRouterAddress));
    }
}
