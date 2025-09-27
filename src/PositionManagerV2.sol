// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {PositionLib} from "./libraries/PositionLib.sol";
import {PositionFactory} from "./PositionFactory.sol";
import {PositionNFT} from "./PositionNFT.sol";
import {MarketManager} from "./MarketManager.sol";

/// @title PositionManager - Lightweight orchestrator for modular position system
/// @notice Coordinates between PositionFactory, PositionNFT, and MarketManager
/// @dev Maintains backward compatibility while delegating to specialized modules
contract PositionManager is Ownable, ReentrancyGuard {
    
    PositionFactory public immutable factory;
    PositionNFT public immutable nft;
    MarketManager public immutable marketManager;

    // Constants for backward compatibility
    uint256 public constant minMargin = 100e6;
    uint256 public constant maxLeverage = 20;

    // Events for backward compatibility
    event PositionOpened(uint256 indexed tokenId, address indexed owner, bytes32 indexed marketId, int256 sizeBase, uint256 entryPrice, uint256 margin);
    event PositionClosed(uint256 indexed tokenId, address indexed owner, int256 pnl);
    event PositionUpdated(uint256 indexed tokenId, int256 newSizeBase, uint256 newMargin);
    event MarginAdded(uint256 indexed tokenId, uint256 amount);
    event MarginRemoved(uint256 indexed tokenId, uint256 amount);
    event MarketAdded(bytes32 indexed marketId, address baseAsset, address quoteAsset, address poolAddress);

    constructor(
        address _factory,
        address _nft,
        address _marketManager
    ) Ownable(msg.sender) {
        factory = PositionFactory(_factory);
        nft = PositionNFT(_nft);
        marketManager = MarketManager(_marketManager);
    }

    /// @notice Open a new perpetual position
    function openPosition(
        bytes32 marketId,
        int256 sizeBase,
        uint256 entryPrice,
        uint256 margin
    ) external nonReentrant returns (uint256 tokenId) {
        tokenId = factory.openPosition(msg.sender, marketId, sizeBase, entryPrice, margin);
        emit PositionOpened(tokenId, msg.sender, marketId, sizeBase, entryPrice, margin);
        return tokenId;
    }

    /// @notice Open a position on behalf of a user
    function openPositionFor(
        address user,
        bytes32 marketId,
        int256 sizeBase,
        uint256 entryPrice,
        uint256 margin
    ) external nonReentrant returns (uint256 tokenId) {
        tokenId = factory.openPosition(user, marketId, sizeBase, entryPrice, margin);
        emit PositionOpened(tokenId, user, marketId, sizeBase, entryPrice, margin);
        return tokenId;
    }

    /// @notice Close a position completely
    function closePosition(uint256 tokenId, uint256 exitPrice) external nonReentrant {
        factory.closePosition(msg.sender, tokenId, exitPrice);
        emit PositionClosed(tokenId, msg.sender, 0); // PnL calculation moved to factory
    }

    /// @notice Update position size and margin
    function updatePosition(uint256 tokenId, int256 newSizeBase, uint256 newMargin) external returns (bool) {
        bool success = factory.updatePosition(msg.sender, tokenId, newSizeBase, newMargin);
        if (success) {
            emit PositionUpdated(tokenId, newSizeBase, newMargin);
        }
        return success;
    }

    /// @notice Update position size and margin on behalf of a user
    function updatePositionFor(address user, uint256 tokenId, int256 newSizeBase, uint256 newMargin) external returns (bool) {
        bool success = factory.updatePosition(user, tokenId, newSizeBase, newMargin);
        if (success) {
            emit PositionUpdated(tokenId, newSizeBase, newMargin);
        }
        return success;
    }

    /// @notice Add margin to an existing position
    function addMargin(uint256 tokenId, uint256 amount) external nonReentrant {
        factory.addMargin(msg.sender, tokenId, amount);
        emit MarginAdded(tokenId, amount);
    }

    /// @notice Remove margin from a position
    function removeMargin(uint256 tokenId, uint256 amount) external nonReentrant {
        factory.removeMargin(msg.sender, tokenId, amount);
        emit MarginRemoved(tokenId, amount);
    }

    /// @notice Add a new trading market
    function addMarket(
        bytes32 marketId,
        address baseAsset,
        address quoteAsset,
        address poolAddress
    ) external onlyOwner {
        marketManager.addMarket(marketId, baseAsset, quoteAsset, poolAddress);
        factory.addMarket(marketId, baseAsset, quoteAsset, poolAddress);
        emit MarketAdded(marketId, baseAsset, quoteAsset, poolAddress);
    }

    /// @notice Update funding index for a market
    function updateFundingIndex(bytes32 marketId, uint256 newIndex) external onlyOwner {
        marketManager.updateFundingIndex(marketId, newIndex);
        factory.updateFundingIndex(marketId, newIndex);
    }

    /// @notice Liquidate a position
    function liquidatePosition(uint256 tokenId, uint256 liquidationPrice) external nonReentrant {
        factory.liquidatePosition(tokenId, liquidationPrice);
    }

    // View functions for backward compatibility
    function getPosition(uint256 tokenId) external view returns (PositionLib.Position memory) {
        return factory.getPosition(tokenId);
    }

    function getMarket(bytes32 marketId) external view returns (PositionLib.Market memory) {
        return factory.getMarket(marketId);
    }

    function getUserPositions(address user) external view returns (uint256[] memory) {
        return factory.getUserPositions(user);
    }

    function getMarketPositions(bytes32 marketId) external view returns (uint256[] memory) {
        return factory.getMarketPositions(marketId);
    }

    /// @notice Get unrealized PnL for a position
    function getUnrealizedPnL(uint256 tokenId, uint256 currentPrice) external view returns (int256) {
        return factory.getUnrealizedPnL(tokenId, currentPrice);
    }

    /// @notice Calculate position's current leverage
    function getCurrentLeverage(uint256 tokenId, uint256 currentPrice) external view returns (uint256) {
        return factory.getCurrentLeverage(tokenId, currentPrice);
    }

    // NFT compatibility functions
    function ownerOf(uint256 tokenId) external view returns (address) {
        return nft.ownerOf(tokenId);
    }

    function balanceOf(address owner) external view returns (uint256) {
        return nft.balanceOf(owner);
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        return nft.tokenURI(tokenId);
    }

    function totalSupply() external view returns (uint256) {
        return nft.totalSupply();
    }

    function tokenByIndex(uint256 index) external view returns (uint256) {
        return nft.tokenByIndex(index);
    }

    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256) {
        return nft.tokenOfOwnerByIndex(owner, index);
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return nft.supportsInterface(interfaceId);
    }
}
