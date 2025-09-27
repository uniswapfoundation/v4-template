// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

/// @title MockHook - Mock implementation for testing
/// @notice Provides mock implementations of hook functions for testing purposes
contract MockHook {
    using PoolIdLibrary for PoolKey;

    // Storage for mock price data
    mapping(bytes32 => uint256) public markPrices;
    mapping(bytes32 => bool) public isMarketActive;

    // Events
    event MarkPriceSet(bytes32 indexed marketId, uint256 price);
    event MarketStatusSet(bytes32 indexed marketId, bool isActive);

    /// @notice Set mock mark price for a market
    /// @param marketId The market identifier
    /// @param price The mock price to set
    function setMarkPrice(bytes32 marketId, uint256 price) external {
        markPrices[marketId] = price;
        emit MarkPriceSet(marketId, price);
    }

    /// @notice Set market active status
    /// @param marketId The market identifier
    /// @param active Whether the market is active
    function setMarketActive(bytes32 marketId, bool active) external {
        isMarketActive[marketId] = active;
        emit MarketStatusSet(marketId, active);
    }

    /// @notice Get mark price for a market (compatible with FundingOracle interface)
    /// @param marketId The market identifier
    /// @return price The current mark price
    function getMarkPrice(bytes32 marketId) external view returns (uint256 price) {
        price = markPrices[marketId];
        require(price > 0, "MockHook: Price not set");
        return price;
    }

    /// @notice Check if market is active
    /// @param marketId The market identifier
    /// @return active Whether the market is active
    function getMarketActive(bytes32 marketId) external view returns (bool active) {
        return isMarketActive[marketId];
    }

    /// @notice Get market state (mock implementation)
    /// @param marketId The market identifier
    /// @return globalFundingIndex Global funding index
    /// @return totalLongOI Total long open interest
    /// @return totalShortOI Total short open interest
    /// @return maxOICap Maximum open interest cap
    /// @return lastFundingTime Last funding time
    /// @return spotPriceFeed Spot price feed address
    /// @return isActive Whether market is active
    function getMarketState(bytes32 marketId) external view returns (
        int256 globalFundingIndex,
        uint256 totalLongOI,
        uint256 totalShortOI,
        uint256 maxOICap,
        uint256 lastFundingTime,
        address spotPriceFeed,
        bool isActive
    ) {
        return (
            1e18, // globalFundingIndex
            0,    // totalLongOI
            0,    // totalShortOI
            0,    // maxOICap
            block.timestamp, // lastFundingTime
            address(0), // spotPriceFeed
            isMarketActive[marketId] // isActive
        );
    }

    // Mock hook permission functions
    function getHookPermissions() external pure returns (uint160) {
        return 0; // No special permissions needed for mock
    }
}
