// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {PositionLib} from "./libraries/PositionLib.sol";
import {MarginAccount} from "./MarginAccount.sol";

interface IPositionNFT {
    function mint(address to, uint256 tokenId) external;
    function burn(uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
    function exists(uint256 tokenId) external view returns (bool);
}

/// @title PositionFactory - Factory contract for position management
/// @notice Handles all position business logic separated from NFT concerns
contract PositionFactory is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using PositionLib for PositionLib.Position;

    // State variables
    IERC20 public immutable USDC;
    MarginAccount public immutable marginAccount;
    IPositionNFT public positionNFT;
    
    uint256 public constant minMargin = 100e6; // 100 USDC
    uint256 public constant maxLeverage = 20;
    uint256 private _nextTokenId = 1;

    // Storage
    mapping(uint256 => PositionLib.Position) public positions;
    mapping(bytes32 => PositionLib.Market) public markets;
    mapping(address => uint256[]) public userPositions;
    mapping(bytes32 => uint256[]) public marketPositions;
    mapping(address => bool) public keyManagers;

    // Events
    event PositionOpened(uint256 indexed tokenId, address indexed owner, bytes32 indexed marketId, int256 sizeBase, uint256 entryPrice, uint256 margin);
    event PositionClosed(uint256 indexed tokenId, address indexed owner, int256 pnl);
    event PositionUpdated(uint256 indexed tokenId, int256 newSizeBase, uint256 newMargin);
    event MarginAdded(uint256 indexed tokenId, uint256 amount);
    event MarginRemoved(uint256 indexed tokenId, uint256 amount);
    event MarketAdded(bytes32 indexed marketId, address baseAsset, address quoteAsset, address poolAddress);
    event KeyManagerAdded(address indexed keyManager);
    event KeyManagerRemoved(address indexed keyManager);

    modifier onlyOwnerOrKeyManager() {
        require(msg.sender == owner() || keyManagers[msg.sender], "Not authorized");
        _;
    }

    constructor(address _usdc, address _marginAccount) Ownable(msg.sender) {
        USDC = IERC20(_usdc);
        marginAccount = MarginAccount(_marginAccount);
    }

    function setPositionNFT(address _positionNFT) external onlyOwner {
        positionNFT = IPositionNFT(_positionNFT);
    }

    function addKeyManager(address keyManager) external onlyOwner {
        require(keyManager != address(0), "Invalid address");
        keyManagers[keyManager] = true;
        emit KeyManagerAdded(keyManager);
    }

    function removeKeyManager(address keyManager) external onlyOwner {
        keyManagers[keyManager] = false;
        emit KeyManagerRemoved(keyManager);
    }

    /// @notice Add a new trading market
    function addMarket(
        bytes32 marketId,
        address baseAsset,
        address quoteAsset,
        address poolAddress
    ) external onlyOwnerOrKeyManager {
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

    /// @notice Open a new position
    function openPosition(
        address user,
        bytes32 marketId,
        int256 sizeBase,
        uint256 entryPrice,
        uint256 margin
    ) external nonReentrant returns (uint256 tokenId) {
        require(address(positionNFT) != address(0), "NFT not set");
        PositionLib.Market memory market = markets[marketId];
        require(market.baseAsset != address(0) && market.isActive, "Invalid market");

        tokenId = _nextTokenId++;
        
        PositionLib.Position memory position = PositionLib.Position({
            owner: user,
            margin: uint96(margin),
            marketId: marketId,
            sizeBase: sizeBase,
            entryPrice: entryPrice,
            lastFundingIndex: market.fundingIndex,
            openedAt: uint64(block.timestamp),
            fundingPaid: 0
        });

        // Validate position parameters
        position.validateOpenPosition(minMargin, maxLeverage);

        // Lock margin
        marginAccount.lockMargin(user, margin);

        // Store position
        positions[tokenId] = position;
        userPositions[user].push(tokenId);
        marketPositions[marketId].push(tokenId);

        // Mint NFT
        positionNFT.mint(user, tokenId);

        emit PositionOpened(tokenId, user, marketId, sizeBase, entryPrice, margin);
    }

    /// @notice Close a position
    function closePosition(uint256 tokenId, uint256 exitPrice) external nonReentrant {
        closePosition(msg.sender, tokenId, exitPrice);
    }

    /// @notice Close a position with explicit user parameter
    function closePosition(address user, uint256 tokenId, uint256 exitPrice) public nonReentrant {
        PositionLib.Position storage position = positions[tokenId];
        position.requirePositionOwner(user);
        require(exitPrice > 0, "Invalid price");

        // Settle funding
        _settleFunding(tokenId);
        
        // Calculate PnL and convert from 18 decimals to 6 decimals (USDC)
        int256 pnl = position.calculatePnL(exitPrice);
        int256 pnlInUsdc = pnl / 1e12; // Convert from 18 decimals to 6 decimals
        marginAccount.settlePnL(user, pnlInUsdc);
        
        // Unlock remaining margin
        uint256 remainingLocked = marginAccount.getLockedBalance(user);
        if (remainingLocked > 0) {
            marginAccount.unlockMargin(user, remainingLocked);
        }

        // Clean up storage
        _removeFromUserPositions(msg.sender, tokenId);
        _removeFromMarketPositions(position.marketId, tokenId);
        delete positions[tokenId];

        // Burn NFT
        positionNFT.burn(tokenId);

        emit PositionClosed(tokenId, msg.sender, pnl);
    }

    /// @notice Update position (for authorized contracts like PerpsRouter)
    function updatePosition(uint256 tokenId, int256 newSizeBase, uint256 newMargin) external returns (bool) {
        return updatePosition(msg.sender, tokenId, newSizeBase, newMargin);
    }

    /// @notice Update position with explicit user parameter (for modular calls)
    function updatePosition(address user, uint256 tokenId, int256 newSizeBase, uint256 newMargin) public returns (bool) {
        PositionLib.Position storage position = positions[tokenId];
        position.requirePositionOwner(user);
        
        if (position.owner == address(0) || newSizeBase == 0 || newMargin < minMargin) return false;
        
        _settleFunding(tokenId);
        position.sizeBase = newSizeBase;
        position.margin = uint96(newMargin);
        
        emit PositionUpdated(tokenId, newSizeBase, newMargin);
        return true;
    }

    /// @notice Add margin to position
    function addMargin(uint256 tokenId, uint256 amount) external nonReentrant {
        addMargin(msg.sender, tokenId, amount);
    }

    /// @notice Add margin to position with explicit user parameter
    function addMargin(address user, uint256 tokenId, uint256 amount) public nonReentrant {
        PositionLib.Position storage position = positions[tokenId];
        position.requirePositionOwner(user);
        require(amount > 0, "Zero amount");

        marginAccount.lockMargin(user, amount);
        position.margin = uint96(uint256(position.margin) + amount);
        
        emit MarginAdded(tokenId, amount);
    }

    /// @notice Remove margin from position
    function removeMargin(uint256 tokenId, uint256 amount) external nonReentrant {
        removeMargin(msg.sender, tokenId, amount);
    }

    /// @notice Remove margin from position with explicit user parameter
    function removeMargin(address user, uint256 tokenId, uint256 amount) public nonReentrant {
        PositionLib.Position storage position = positions[tokenId];
        position.requirePositionOwner(user);
        require(amount > 0 && amount <= position.margin, "Invalid amount");

        uint256 newMargin = uint256(position.margin) - amount;
        if (newMargin < minMargin) revert PositionLib.InsufficientMargin();

        uint256 notionalValue = (uint256(position.sizeBase > 0 ? position.sizeBase : -position.sizeBase) * position.entryPrice) / 1e18;
        require(notionalValue <= newMargin * 1e12 * maxLeverage, "Exceeds leverage");

        position.margin = uint96(newMargin);
        marginAccount.unlockMargin(user, amount);
        
        emit MarginRemoved(tokenId, amount);
    }

    /// @notice Update funding index for a market
    function updateFundingIndex(bytes32 marketId, uint256 newIndex) external onlyOwner {
        markets[marketId].fundingIndex = newIndex;
        markets[marketId].lastFundingUpdate = uint64(block.timestamp);
    }

    /// @notice Liquidate a position
    function liquidatePosition(uint256 tokenId, uint256 liquidationPrice) external nonReentrant {
        PositionLib.Position storage position = positions[tokenId];
        require(position.owner != address(0), "Position not found");

        address positionOwner = position.owner;
        
        // Calculate PnL for event emission (18 decimals)
        int256 pnl = position.calculatePnL(liquidationPrice);
        
        // Note: PnL settlement is handled by LiquidationEngine before this call
        // No need to settle PnL again or check liquidation condition
        
        // Clean up position
        _removeFromUserPositions(positionOwner, tokenId);
        _removeFromMarketPositions(position.marketId, tokenId);
        delete positions[tokenId];
        
        positionNFT.burn(tokenId);
        
        emit PositionClosed(tokenId, positionOwner, pnl);
    }

    // View functions
    function getPosition(uint256 tokenId) external view returns (PositionLib.Position memory) {
        return positions[tokenId];
    }

    function getMarket(bytes32 marketId) external view returns (PositionLib.Market memory) {
        return markets[marketId];
    }

    function getUserPositions(address user) external view returns (uint256[] memory) {
        return userPositions[user];
    }

    function getMarketPositions(bytes32 marketId) external view returns (uint256[] memory) {
        return marketPositions[marketId];
    }

    /// @notice Get unrealized PnL for a position
    function getUnrealizedPnL(uint256 tokenId, uint256 currentPrice) external view returns (int256) {
        PositionLib.Position memory position = positions[tokenId];
        require(position.owner != address(0), "Position not found");
        return _calculatePnLIn18Decimals(position, currentPrice);
    }

    /// @notice Calculate position's current leverage
    function getCurrentLeverage(uint256 tokenId, uint256 currentPrice) external view returns (uint256) {
        PositionLib.Position memory position = positions[tokenId];
        require(position.owner != address(0), "Position not found");

        uint256 notionalValue = (uint256(position.sizeBase > 0 ? position.sizeBase : -position.sizeBase) * currentPrice) / 1e18;
        uint256 marginIn18Decimals = uint256(position.margin) * 1e12;
        return (notionalValue * 1e18) / marginIn18Decimals;
    }

    /// @notice Calculate PnL in 18 decimals
    function _calculatePnLIn18Decimals(PositionLib.Position memory position, uint256 currentPrice) internal pure returns (int256) {
        if (position.sizeBase == 0) return 0;
        int256 priceDiff = int256(currentPrice) - int256(position.entryPrice);
        return (position.sizeBase * priceDiff) / 1e18;
    }

    // Internal functions
    function _settleFunding(uint256 tokenId) internal {
        PositionLib.Position storage position = positions[tokenId];
        PositionLib.Market memory market = markets[position.marketId];
        position.settleFunding(market.fundingIndex);
    }

    function _removeFromUserPositions(address user, uint256 tokenId) internal {
        uint256[] storage userPositionsList = userPositions[user];
        for (uint256 i = 0; i < userPositionsList.length; i++) {
            if (userPositionsList[i] == tokenId) {
                userPositionsList[i] = userPositionsList[userPositionsList.length - 1];
                userPositionsList.pop();
                break;
            }
        }
    }

    function _removeFromMarketPositions(bytes32 marketId, uint256 tokenId) internal {
        uint256[] storage marketPositionsList = marketPositions[marketId];
        for (uint256 i = 0; i < marketPositionsList.length; i++) {
            if (marketPositionsList[i] == tokenId) {
                marketPositionsList[i] = marketPositionsList[marketPositionsList.length - 1];
                marketPositionsList.pop();
                break;
            }
        }
    }
}
