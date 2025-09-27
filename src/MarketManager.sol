// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PositionLib} from "./libraries/PositionLib.sol";

/// @title MarketManager - Manages trading markets and funding
/// @notice Handles market configuration and funding rate updates
contract MarketManager is Ownable {
    using PositionLib for PositionLib.Market;

    mapping(bytes32 => PositionLib.Market) public markets;
    mapping(bytes32 => uint256[]) public marketPositions;
    mapping(address => bool) public keyManagers;
    
    event MarketAdded(bytes32 indexed marketId, address baseAsset, address quoteAsset, address poolAddress);
    event MarketStatusUpdated(bytes32 indexed marketId, bool isActive);
    event FundingIndexUpdated(bytes32 indexed marketId, uint256 newIndex);
    event KeyManagerAdded(address indexed keyManager);
    event KeyManagerRemoved(address indexed keyManager);

    modifier onlyOwnerOrKeyManager() {
        require(msg.sender == owner() || keyManagers[msg.sender], "Not authorized");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /// @notice Add a new trading market
    function addKeyManager(address keyManager) external onlyOwner {
        require(keyManager != address(0), "Invalid address");
        keyManagers[keyManager] = true;
        emit KeyManagerAdded(keyManager);
    }

    function removeKeyManager(address keyManager) external onlyOwner {
        keyManagers[keyManager] = false;
        emit KeyManagerRemoved(keyManager);
    }

    function addMarket(
        bytes32 marketId,
        address baseAsset,
        address quoteAsset,
        address poolAddress
    ) external onlyOwnerOrKeyManager {
        _addMarket(marketId, baseAsset, quoteAsset, poolAddress);
    }

    function addMarket(
        bytes32 marketId,
        address baseAsset,
        address quoteAsset,
        address poolAddress,
        uint24 fee
    ) external onlyOwnerOrKeyManager {
        _addMarket(marketId, baseAsset, quoteAsset, poolAddress);
    }

    function _addMarket(
        bytes32 marketId,
        address baseAsset,
        address quoteAsset,
        address poolAddress
    ) internal {
        require(markets[marketId].baseAsset == address(0), "Market exists");
        
        markets[marketId] = PositionLib.Market({
            baseAsset: baseAsset,
            quoteAsset: quoteAsset,
            poolAddress: poolAddress,
            lastFundingUpdate: uint64(block.timestamp),
            isActive: true,
            fundingIndex: 1e18
        });

        emit MarketAdded(marketId, baseAsset, quoteAsset, poolAddress);
    }

    /// @notice Update market status
    function updateMarketStatus(bytes32 marketId, bool isActive) external onlyOwnerOrKeyManager {
        require(markets[marketId].baseAsset != address(0), "Market not found");
        markets[marketId].isActive = isActive;
        emit MarketStatusUpdated(marketId, isActive);
    }

    /// @notice Update funding index for a market
    function updateFundingIndex(bytes32 marketId, uint256 newIndex) external onlyOwner {
        require(markets[marketId].baseAsset != address(0), "Market not found");
        markets[marketId].fundingIndex = newIndex;
        markets[marketId].lastFundingUpdate = uint64(block.timestamp);
        emit FundingIndexUpdated(marketId, newIndex);
    }

    /// @notice Get market information
    function getMarket(bytes32 marketId) external view returns (PositionLib.Market memory) {
        return markets[marketId];
    }

    /// @notice Check if market is active
    function isMarketActive(bytes32 marketId) external view returns (bool) {
        return markets[marketId].isActive;
    }

    /// @notice Get current funding index
    function getFundingIndex(bytes32 marketId) external view returns (uint256) {
        return markets[marketId].fundingIndex;
    }

    /// @notice Add position to market tracking
    function addPositionToMarket(bytes32 marketId, uint256 tokenId) external {
        // This would be called by the factory
        marketPositions[marketId].push(tokenId);
    }

    /// @notice Remove position from market tracking
    function removePositionFromMarket(bytes32 marketId, uint256 tokenId) external {
        uint256[] storage positions = marketPositions[marketId];
        for (uint256 i = 0; i < positions.length; i++) {
            if (positions[i] == tokenId) {
                positions[i] = positions[positions.length - 1];
                positions.pop();
                break;
            }
        }
    }

    /// @notice Get all positions in a market
    function getMarketPositions(bytes32 marketId) external view returns (uint256[] memory) {
        return marketPositions[marketId];
    }
}
