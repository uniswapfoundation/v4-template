// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {PositionLib} from "./libraries/PositionLib.sol";
import {PositionManager} from "./PositionManagerV2.sol";
import {PositionFactory} from "./PositionFactory.sol";
import {MarginAccount} from "./MarginAccount.sol";
import {FundingOracle} from "./FundingOracle.sol";
import {InsuranceFund} from "./InsuranceFund.sol";

/// @title LiquidationEngine - Automated liquidation system for undercollateralized positions
/// @notice Monitors positions and liquidates them when they fall below maintenance margin requirements
/// @dev Integrates with all core system components to ensure system solvency
contract LiquidationEngine is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Liquidation configuration for a market
    struct LiquidationConfig {
        uint256 maintenanceMarginRatio; // Maintenance margin ratio (e.g., 500 = 5%)
        uint256 liquidationFeeRate;     // Fee paid to liquidator (e.g., 50 = 0.5%)
        uint256 insuranceFeeRate;       // Fee paid to insurance fund (e.g., 25 = 0.25%)
        bool isActive;                  // Whether liquidations are active for this market
    }

    /// @notice Information about a liquidation event
    struct LiquidationInfo {
        uint256 tokenId;                // Position token ID
        address liquidator;             // Address that performed the liquidation
        address positionOwner;          // Original position owner
        uint256 liquidationPrice;       // Price at which position was liquidated
        uint256 positionSize;           // Size of the liquidated position
        uint256 margin;                 // Margin amount in the position
        int256 pnl;                     // Realized P&L from liquidation
        uint256 liquidationFee;         // Fee paid to liquidator
        uint256 insuranceFee;           // Fee paid to insurance fund
        uint256 timestamp;              // Liquidation timestamp
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Core system contracts
    PositionManager public immutable positionManager;
    PositionFactory public immutable positionFactory;
    MarginAccount public immutable marginAccount;
    FundingOracle public immutable fundingOracle;
    InsuranceFund public immutable insuranceFund;
    IERC20 public immutable USDC;

    /// @notice Liquidation configurations by market ID
    mapping(bytes32 => LiquidationConfig) public liquidationConfigs;

    /// @notice Liquidation history
    mapping(uint256 => LiquidationInfo) public liquidations;
    
    /// @notice Array of all liquidated token IDs for enumeration
    uint256[] public liquidatedTokenIds;

    /// @notice Minimum position size for liquidation (to avoid dust liquidations)
    uint256 public minLiquidationSize = 1e6; // $1 minimum

    /// @notice Maximum number of positions to check per liquidation call (gas optimization)
    uint256 public maxPositionsPerCheck = 50;

    /// @notice Default liquidation parameters
    uint256 public constant DEFAULT_MAINTENANCE_MARGIN_RATIO = 500; // 5%
    uint256 public constant DEFAULT_LIQUIDATION_FEE_RATE = 50; // 0.5%
    uint256 public constant DEFAULT_INSURANCE_FEE_RATE = 25; // 0.25%
    uint256 public constant BPS_DENOMINATOR = 10000;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event PositionLiquidated(
        uint256 indexed tokenId,
        address indexed liquidator,
        address indexed positionOwner,
        bytes32 marketId,
        uint256 liquidationPrice,
        uint256 positionSize,
        int256 pnl,
        uint256 liquidationFee,
        uint256 insuranceFee
    );

    event LiquidationConfigUpdated(
        bytes32 indexed marketId,
        uint256 maintenanceMarginRatio,
        uint256 liquidationFeeRate,
        uint256 insuranceFeeRate,
        bool isActive
    );

    event LiquidatorRewardPaid(
        address indexed liquidator,
        uint256 amount
    );

    event InsuranceFundContribution(
        uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error PositionNotLiquidatable();
    error PositionNotFound();
    error MarketNotConfigured();
    error LiquidationsDisabled();
    error InsufficientPositionSize();
    error UnauthorizedLiquidator();

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _positionManager,
        address _positionFactory,
        address _marginAccount,
        address _fundingOracle,
        address payable _insuranceFund,
        address _usdc
    ) Ownable(msg.sender) {
        positionManager = PositionManager(_positionManager);
        positionFactory = PositionFactory(_positionFactory);
        marginAccount = MarginAccount(_marginAccount);
        fundingOracle = FundingOracle(payable(_fundingOracle));
        insuranceFund = InsuranceFund(_insuranceFund);
        USDC = IERC20(_usdc);
    }

    /*//////////////////////////////////////////////////////////////
                          LIQUIDATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Liquidate a specific position if it's undercollateralized
    /// @param tokenId Position token ID to liquidate
    function liquidatePosition(uint256 tokenId) external nonReentrant {
        _liquidatePositionInternal(tokenId);
    }

    /// @notice Liquidate multiple positions in batch
    /// @param tokenIds Array of position token IDs to liquidate
    function liquidatePositions(uint256[] calldata tokenIds) external nonReentrant {
        uint256 length = tokenIds.length;
        require(length <= maxPositionsPerCheck, "Too many positions");

        uint256 liquidatedCount = 0;
        
        for (uint256 i = 0; i < length; i++) {
            uint256 tokenId = tokenIds[i];
            
            try this._liquidatePositionInternal(tokenId) {
                liquidatedCount++;
            } catch {
                // Skip failed liquidations and continue
                continue;
            }
        }

        require(liquidatedCount > 0, "No positions liquidated");
    }

    /// @notice Internal liquidation logic without reentrancy guard
    /// @param tokenId Position token ID to liquidate
    function _liquidatePositionInternal(uint256 tokenId) public {
        PositionLib.Position memory position = positionManager.getPosition(tokenId);
        if (position.owner == address(0)) revert PositionNotFound();

        LiquidationConfig memory config = liquidationConfigs[position.marketId];
        if (config.maintenanceMarginRatio == 0) revert MarketNotConfigured();
        if (!config.isActive) revert LiquidationsDisabled();

        // Check if position is liquidatable
        (bool isLiquidatable, uint256 currentPrice) = _isPositionLiquidatable(tokenId, position, config);
        if (!isLiquidatable) revert PositionNotLiquidatable();

        // Calculate position value
        uint256 positionValue = (uint256(position.sizeBase > 0 ? position.sizeBase : -position.sizeBase) * currentPrice) / 1e18;
        if (positionValue < minLiquidationSize) revert InsufficientPositionSize();

        // Execute liquidation
        _executeLiquidation(tokenId, position, config, currentPrice);
    }

    /// @notice Check if a position can be liquidated
    /// @param tokenId Position token ID
    /// @return isLiquidatable Whether the position can be liquidated
    /// @return currentPrice Current mark price
    /// @return healthFactor Position health factor (1e18 = 100%)
    function isPositionLiquidatable(uint256 tokenId) external view returns (
        bool isLiquidatable,
        uint256 currentPrice,
        uint256 healthFactor
    ) {
        PositionLib.Position memory position = positionManager.getPosition(tokenId);
        if (position.owner == address(0)) return (false, 0, 0);

        LiquidationConfig memory config = liquidationConfigs[position.marketId];
        if (!config.isActive || config.maintenanceMarginRatio == 0) {
            return (false, 0, 0);
        }

        (isLiquidatable, currentPrice) = _isPositionLiquidatable(tokenId, position, config);
        healthFactor = _calculateHealthFactor(position, currentPrice, config);
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Check if a position is liquidatable
    function _isPositionLiquidatable(
        uint256 tokenId,
        PositionLib.Position memory position,
        LiquidationConfig memory config
    ) internal view returns (bool isLiquidatable, uint256 currentPrice) {
        // Get current mark price
        currentPrice = fundingOracle.getMarkPrice(
            PoolId.wrap(position.marketId)
        );

        // Calculate unrealized PnL
        int256 unrealizedPnl = positionManager.getUnrealizedPnL(tokenId, currentPrice);
        
        // Calculate effective margin (margin + unrealized PnL)
        // Convert USDC margin (6 decimals) to 18 decimals for comparison
        int256 marginIn18Decimals = int256(uint256(position.margin)) * 1e12;
        int256 effectiveMargin = marginIn18Decimals + unrealizedPnl;
        
        // Position is liquidatable if effective margin < maintenance margin requirement
        uint256 positionValue = (uint256(position.sizeBase > 0 ? position.sizeBase : -position.sizeBase) * currentPrice) / 1e18;
        uint256 maintenanceMargin = (positionValue * config.maintenanceMarginRatio) / BPS_DENOMINATOR;
        
        isLiquidatable = effectiveMargin < int256(maintenanceMargin);
    }

    /// @notice Calculate position health factor
    function _calculateHealthFactor(
        PositionLib.Position memory position,
        uint256 currentPrice,
        LiquidationConfig memory config
    ) internal pure returns (uint256 healthFactor) {
        // Get unrealized PnL in 18 decimals
        int256 priceDiff = int256(currentPrice) - int256(position.entryPrice);
        int256 unrealizedPnl = (position.sizeBase * priceDiff) / 1e18;
        
        // Calculate effective margin in 18 decimals
        int256 marginIn18Decimals = int256(uint256(position.margin)) * 1e12; // Convert USDC to 18 decimals
        int256 effectiveMargin = marginIn18Decimals + unrealizedPnl;
        
        // Calculate required maintenance margin in 18 decimals
        uint256 positionValue = (uint256(position.sizeBase > 0 ? position.sizeBase : -position.sizeBase) * currentPrice) / 1e18;
        uint256 maintenanceMargin = (positionValue * config.maintenanceMarginRatio) / BPS_DENOMINATOR;
        
        // Health factor = effective margin / maintenance margin (1e18 scale)
        if (maintenanceMargin == 0) return type(uint256).max;
        if (effectiveMargin <= 0) return 0;
        
        healthFactor = (uint256(effectiveMargin) * 1e18) / maintenanceMargin;
    }

    /// @notice Execute the liquidation of a position
    function _executeLiquidation(
        uint256 tokenId,
        PositionLib.Position memory position,
        LiquidationConfig memory config,
        uint256 liquidationPrice
    ) internal {
        // Calculate PnL at liquidation
        int256 pnl = _calculatePnL(position, liquidationPrice);
        
        // Calculate fees
        uint256 positionValue = (uint256(position.sizeBase > 0 ? position.sizeBase : -position.sizeBase) * liquidationPrice) / 1e18;
        uint256 liquidationFee = (positionValue * config.liquidationFeeRate) / BPS_DENOMINATOR;
        uint256 insuranceFee = (positionValue * config.insuranceFeeRate) / BPS_DENOMINATOR;
        
        // Settle PnL through MarginAccount
        marginAccount.settlePnL(position.owner, pnl);
        
        // Close position through PositionFactory's liquidation function
        positionFactory.liquidatePosition(tokenId, liquidationPrice);
        
        // Handle liquidation and insurance fees
        // Transfer liquidation fee to liquidator
        if (liquidationFee > 0) {
            uint256 liquidationFeeUSDC = liquidationFee / 1e12; // Convert from 18 decimals to 6 decimals for USDC
            marginAccount.transferBetweenUsers(position.owner, msg.sender, liquidationFeeUSDC);
            // Withdraw fee to liquidator's wallet
            marginAccount.withdrawFor(msg.sender, liquidationFeeUSDC);
        }
        
        // Transfer insurance fee to insurance fund
        if (insuranceFee > 0) {
            uint256 insuranceFeeUSDC = insuranceFee / 1e12; // Convert from 18 decimals to 6 decimals for USDC
            marginAccount.transferBetweenUsers(position.owner, address(insuranceFund), insuranceFeeUSDC);
            // Withdraw fee to insurance fund's wallet
            marginAccount.withdrawFor(address(insuranceFund), insuranceFeeUSDC);
            // Update insurance fund accounting
            insuranceFund.collectFee(insuranceFeeUSDC);
        }
        
        // Store liquidation info
        liquidations[tokenId] = LiquidationInfo({
            tokenId: tokenId,
            liquidator: msg.sender,
            positionOwner: position.owner,
            liquidationPrice: liquidationPrice,
            positionSize: uint256(position.sizeBase > 0 ? position.sizeBase : -position.sizeBase),
            margin: position.margin,
            pnl: pnl,
            liquidationFee: liquidationFee,
            insuranceFee: insuranceFee,
            timestamp: block.timestamp
        });
        
        liquidatedTokenIds.push(tokenId);
        
        emit PositionLiquidated(
            tokenId,
            msg.sender,
            position.owner,
            position.marketId,
            liquidationPrice,
            uint256(position.sizeBase > 0 ? position.sizeBase : -position.sizeBase),
            pnl,
            liquidationFee,
            insuranceFee
        );
    }

    /// @notice Calculate PnL for a position
    function _calculatePnL(
        PositionLib.Position memory position,
        uint256 currentPrice
    ) internal pure returns (int256) {
        if (position.sizeBase == 0) return 0;
        
        int256 priceDiff = int256(currentPrice) - int256(position.entryPrice);
        int256 pnlIn18Decimals = (position.sizeBase * priceDiff) / 1e18;
        return pnlIn18Decimals / 1e12; // Convert to 6 decimals for USDC
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Configure liquidation parameters for a market
    /// @param marketId Market identifier
    /// @param maintenanceMarginRatio Maintenance margin ratio in basis points
    /// @param liquidationFeeRate Liquidation fee rate in basis points
    /// @param insuranceFeeRate Insurance fee rate in basis points
    /// @param isActive Whether liquidations are active
    function configureLiquidation(
        bytes32 marketId,
        uint256 maintenanceMarginRatio,
        uint256 liquidationFeeRate,
        uint256 insuranceFeeRate,
        bool isActive
    ) external onlyOwner {
        require(maintenanceMarginRatio > 0 && maintenanceMarginRatio < 10000, "Invalid maintenance margin ratio");
        require(liquidationFeeRate < 1000, "Invalid liquidation fee rate"); // Max 10%
        require(insuranceFeeRate < 1000, "Invalid insurance fee rate"); // Max 10%

        liquidationConfigs[marketId] = LiquidationConfig({
            maintenanceMarginRatio: maintenanceMarginRatio,
            liquidationFeeRate: liquidationFeeRate,
            insuranceFeeRate: insuranceFeeRate,
            isActive: isActive
        });

        emit LiquidationConfigUpdated(
            marketId,
            maintenanceMarginRatio,
            liquidationFeeRate,
            insuranceFeeRate,
            isActive
        );
    }

    /// @notice Set minimum liquidation size
    /// @param _minLiquidationSize Minimum position size for liquidation
    function setMinLiquidationSize(uint256 _minLiquidationSize) external onlyOwner {
        minLiquidationSize = _minLiquidationSize;
    }

    /// @notice Set maximum positions per check
    /// @param _maxPositionsPerCheck Maximum positions to check in one call
    function setMaxPositionsPerCheck(uint256 _maxPositionsPerCheck) external onlyOwner {
        maxPositionsPerCheck = _maxPositionsPerCheck;
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get liquidation configuration for a market
    /// @param marketId Market identifier
    /// @return config Liquidation configuration
    function getLiquidationConfig(bytes32 marketId) external view returns (LiquidationConfig memory) {
        return liquidationConfigs[marketId];
    }

    /// @notice Get liquidation information for a token ID
    /// @param tokenId Position token ID
    /// @return info Liquidation information
    function getLiquidationInfo(uint256 tokenId) external view returns (LiquidationInfo memory) {
        return liquidations[tokenId];
    }

    /// @notice Get total number of liquidations
    /// @return count Total liquidation count
    function getTotalLiquidations() external view returns (uint256) {
        return liquidatedTokenIds.length;
    }

    /// @notice Get liquidated token IDs in a range
    /// @param start Start index
    /// @param end End index
    /// @return tokenIds Array of liquidated token IDs
    function getLiquidatedTokenIds(uint256 start, uint256 end) external view returns (uint256[] memory) {
        require(start <= end && end < liquidatedTokenIds.length, "Invalid range");
        
        uint256 length = end - start + 1;
        uint256[] memory tokenIds = new uint256[](length);
        
        for (uint256 i = 0; i < length; i++) {
            tokenIds[i] = liquidatedTokenIds[start + i];
        }
        
        return tokenIds;
    }
}
