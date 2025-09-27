// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title PositionLib - Library for perpetual trading position management
/// @notice Contains all position-related data structures and core logic
library PositionLib {
    /// @notice Structure representing a perpetual trading position
    struct Position {
        address owner;              // 20 bytes
        uint96 margin;             // 12 bytes - collateral amount in USDC (max 79M USDC)
        bytes32 marketId;          // 32 bytes
        int256 sizeBase;           // 32 bytes - positive = long, negative = short
        uint256 entryPrice;        // 32 bytes - in 1e18 precision
        uint256 lastFundingIndex;  // 32 bytes - last funding index
        uint64 openedAt;           // 8 bytes - timestamp (sufficient until year 2554)
        int256 fundingPaid;        // 32 bytes - total funding paid/received
    }

    /// @notice Market information structure
    struct Market {
        address baseAsset;         // 20 bytes - Base asset token address
        address quoteAsset;        // 20 bytes - Quote asset token address (USDC)
        address poolAddress;       // 20 bytes - Uniswap V4 pool address
        uint64 lastFundingUpdate;  // 8 bytes - Last funding update timestamp
        bool isActive;             // 1 byte - Market active status
        uint256 fundingIndex;      // 32 bytes - Current cumulative funding index
    }

    // Custom errors
    error NotPositionOwner();
    error InsufficientMargin();
    error ExceedsMaxLeverage();
    error PositionNotFound();
    error MarketNotFound();
    error MarketNotActive();
    error InvalidPositionSize();
    error InvalidPrice();
    error ZeroAmount();

    /// @notice Calculate PnL for a position at a given price
    function calculatePnL(Position memory position, uint256 currentPrice) internal pure returns (int256) {
        if (position.sizeBase == 0) return 0;
        
        int256 priceDiff = int256(currentPrice) - int256(position.entryPrice);
        return (position.sizeBase * priceDiff) / 1e18;
    }

    /// @notice Calculate funding payment for a position
    function calculateFundingPayment(
        Position memory position,
        uint256 currentFundingIndex
    ) internal pure returns (int256) {
        if (position.sizeBase == 0) return 0;
        
        int256 indexDiff = int256(currentFundingIndex) - int256(position.lastFundingIndex);
        return (position.sizeBase * indexDiff) / 1e18;
    }

    /// @notice Validate position opening parameters
    function validateOpenPosition(
        Position memory position,
        uint256 minMargin,
        uint256 maxLeverage
    ) internal pure {
        if (position.margin < minMargin) revert InsufficientMargin();
        if (position.sizeBase == 0) revert InvalidPositionSize();
        if (position.entryPrice == 0) revert InvalidPrice();

        uint256 notionalValue = (uint256(position.sizeBase > 0 ? position.sizeBase : -position.sizeBase) * position.entryPrice) / 1e18;
        if (notionalValue > uint256(position.margin) * 1e12 * maxLeverage) revert ExceedsMaxLeverage();
    }

    /// @notice Update position funding
    function settleFunding(
        Position storage position,
        uint256 currentFundingIndex
    ) internal {
        int256 fundingPayment = calculateFundingPayment(position, currentFundingIndex);
        position.fundingPaid += fundingPayment;
        position.lastFundingIndex = currentFundingIndex;
    }

    /// @notice Check if position owner or authorized
    function requirePositionOwner(Position memory position, address caller) internal pure {
        if (position.owner != caller) revert NotPositionOwner();
    }
}
