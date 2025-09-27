// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

import {MarginAccount} from "./MarginAccount.sol";
import {PositionLib} from "./libraries/PositionLib.sol";
import {PositionManager} from "./PositionManagerV2.sol";
import {PositionFactory} from "./PositionFactory.sol";
import {PerpsHook} from "./PerpsHook.sol";
import {FundingOracle} from "./FundingOracle.sol";

/// @title PerpsRouter - User-Friendly Perpetual Futures Interface
/// @notice Simplifies perpetual futures trading by bundling complex operations
/// @dev This contract provides a clean interface for users to trade perpetuals
contract PerpsRouter is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using PoolIdLibrary for PoolKey;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Core protocol contracts
    MarginAccount public immutable marginAccount;
    PositionManager public immutable positionManager;
    PositionFactory public immutable positionFactory;
    FundingOracle public immutable fundingOracle;
    IPoolManager public immutable poolManager;
    IERC20 public immutable USDC;

    /// @notice Default slippage tolerance (1%)
    uint256 public constant DEFAULT_SLIPPAGE_BPS = 100;
    uint256 public constant MAX_SLIPPAGE_BPS = 2000; // 20%
    uint256 public constant BPS_DENOMINATOR = 10000;

    /// @notice Maximum leverage allowed
    uint256 public constant MAX_LEVERAGE = 20;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Parameters for opening a position
    struct OpenPositionParams {
        PoolKey poolKey;           // Uniswap pool key
        bool isLong;               // True for long, false for short
        uint256 marginAmount;      // Margin in USDC (6 decimals)
        uint256 leverage;          // Leverage multiplier (1e18 = 1x)
        uint256 slippageBps;       // Slippage tolerance in basis points
        uint256 deadline;          // Transaction deadline
    }

    /// @notice Parameters for closing a position  
    struct ClosePositionParams {
        uint256 tokenId;           // Position NFT token ID
        uint256 sizeBps;           // Percentage to close (10000 = 100%)
        uint256 slippageBps;       // Slippage tolerance in basis points
        uint256 deadline;          // Transaction deadline
    }

    /// @notice Parameters for modifying margin
    struct MarginParams {
        uint256 tokenId;           // Position NFT token ID
        uint256 amount;            // Amount to add/remove
        uint256 deadline;          // Transaction deadline
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event PositionOpened(
        address indexed user,
        uint256 indexed tokenId,
        PoolId indexed poolId,
        bool isLong,
        uint256 size,
        uint256 margin,
        uint256 leverage
    );

    event PositionClosed(
        address indexed user,
        uint256 indexed tokenId,
        PoolId indexed poolId,
        uint256 sizeReduced,
        int256 pnl
    );

    event MarginAdded(
        address indexed user,
        uint256 indexed tokenId,
        uint256 amount
    );

    event MarginRemoved(
        address indexed user,
        uint256 indexed tokenId,
        uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidLeverage();
    error InvalidSlippage();
    error DeadlineExpired();
    error InsufficientMargin();
    error PositionNotFound();
    error NotPositionOwner();
    error InvalidCloseSize();
    error SlippageExceeded();
    error MarketNotActive();

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyValidDeadline(uint256 deadline) {
        if (block.timestamp > deadline) revert DeadlineExpired();
        _;
    }

    modifier onlyPositionOwner(uint256 tokenId) {
        if (positionManager.ownerOf(tokenId) != msg.sender) revert NotPositionOwner();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _marginAccount,
        address _positionManager,
        address _positionFactory,
        address _fundingOracle,
        address _poolManager,
        address _usdc
    ) {
        marginAccount = MarginAccount(_marginAccount);
        positionManager = PositionManager(_positionManager);
        positionFactory = PositionFactory(_positionFactory);
        fundingOracle = FundingOracle(payable(_fundingOracle));
        poolManager = IPoolManager(_poolManager);
        USDC = IERC20(_usdc);
    }

    /*//////////////////////////////////////////////////////////////
                            TRADING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Open a new perpetual position with automatic margin management
    /// @param params Position parameters
    /// @return tokenId The NFT token ID of the new position
    function openPosition(OpenPositionParams calldata params) 
        external 
        nonReentrant 
        onlyValidDeadline(params.deadline)
        returns (uint256 tokenId) 
    {
        _validateOpenParams(params);

        // Calculate position size based on margin and leverage
        uint256 markPrice = fundingOracle.getMarkPrice(params.poolKey.toId());
        uint256 notionalSize = (params.marginAmount * 1e12 * params.leverage) / 1e18; // Convert USDC to 18 decimals
        uint256 baseSize = (notionalSize * 1e18) / markPrice; // Calculate base asset size

        // Transfer USDC from user to margin account and credit their balance
        USDC.safeTransferFrom(msg.sender, address(marginAccount), params.marginAmount);
        marginAccount.depositFor(msg.sender, params.marginAmount);

        // Create position in PositionManager (this will lock the margin)
        bytes32 marketId = bytes32(PoolId.unwrap(params.poolKey.toId()));
        int256 sizeBase = params.isLong ? int256(baseSize) : -int256(baseSize);
        
        tokenId = positionManager.openPositionFor(
            msg.sender,
            marketId,
            sizeBase,
            markPrice,
            params.marginAmount
        );

        emit PositionOpened(
            msg.sender,
            tokenId,
            params.poolKey.toId(),
            params.isLong,
            baseSize,
            params.marginAmount,
            params.leverage
        );
    }

    /// @notice Close a position (partially or completely)
    /// @param params Close parameters
    function closePosition(ClosePositionParams calldata params) 
        external 
        nonReentrant
        onlyValidDeadline(params.deadline)
        onlyPositionOwner(params.tokenId)
    {
        _validateCloseParams(params);

        // Get position details
        PositionLib.Position memory position = positionManager.getPosition(params.tokenId);
        
        // Calculate current mark price
        PoolId poolId = PoolId.wrap(position.marketId);
        uint256 currentPrice = fundingOracle.getMarkPrice(poolId);
        
        // Calculate size to close
        uint256 absoluteSize = uint256(position.sizeBase > 0 ? position.sizeBase : -position.sizeBase);
        uint256 sizeToClose = (absoluteSize * params.sizeBps) / BPS_DENOMINATOR;
        
        if (params.sizeBps == BPS_DENOMINATOR) {
            // Full close - calculate PnL and handle manually
            int256 pnl = _calculatePartialPnL(position, currentPrice, params.sizeBps);
            
            // Settle full PnL and release all margin
            marginAccount.settlePnL(msg.sender, pnl);
            marginAccount.unlockMargin(msg.sender, position.margin);
            
            // Set position size to 0 and margin to 0 (effectively closing it)
            positionManager.updatePositionFor(msg.sender, params.tokenId, 0, 0);
        } else {
            // Partial close - calculate partial PnL and handle manually
            int256 pnl = _calculatePartialPnL(position, currentPrice, params.sizeBps);
            uint256 marginToRelease = (position.margin * params.sizeBps) / BPS_DENOMINATOR;
            
            // Settle partial PnL
            marginAccount.settlePnL(msg.sender, pnl);
            marginAccount.unlockMargin(msg.sender, marginToRelease);
            
            // Update position size and margin in PositionManager
            // Note: This requires PositionManager to support partial reduction
            // For now, we'll implement a simple version
            _reducePosition(msg.sender, params.tokenId, sizeToClose, marginToRelease);
        }

        emit PositionClosed(msg.sender, params.tokenId, poolId, sizeToClose, 0); // PnL calculated internally
    }

    /// @notice Add margin to an existing position
    /// @param params Margin parameters
    function addMargin(MarginParams calldata params) 
        external 
        nonReentrant
        onlyValidDeadline(params.deadline)
        onlyPositionOwner(params.tokenId)
    {
        require(params.amount > 0, "Amount must be positive");

        // Transfer USDC from user to margin account and credit their balance
        USDC.safeTransferFrom(msg.sender, address(marginAccount), params.amount);
        marginAccount.depositFor(msg.sender, params.amount);
        
        // Lock margin in margin account
        marginAccount.lockMargin(msg.sender, params.amount);
        
        // Get current position to calculate new margin
        PositionLib.Position memory position = positionManager.getPosition(params.tokenId);
        uint256 newMargin = position.margin + params.amount;
        
        // Update position with new margin
        positionManager.updatePositionFor(msg.sender, params.tokenId, position.sizeBase, newMargin);

        emit MarginAdded(msg.sender, params.tokenId, params.amount);
    }

    /// @notice Remove margin from a position (if safe)
    /// @param params Margin parameters  
    function removeMargin(MarginParams calldata params)
        external
        nonReentrant
        onlyValidDeadline(params.deadline)
        onlyPositionOwner(params.tokenId)
    {
        require(params.amount > 0, "Amount must be positive");

        // Get current position to calculate new margin and verify removal is safe
        PositionLib.Position memory position = positionManager.getPosition(params.tokenId);
        require(position.margin >= params.amount, "Insufficient margin");
        
        uint256 newMargin = position.margin - params.amount;
        
        // Check if remaining margin maintains minimum requirements
        require(newMargin >= positionManager.minMargin(), "Below minimum margin");
        
        // Update position with new margin
        positionManager.updatePosition(params.tokenId, position.sizeBase, newMargin);
        
        // Unlock margin from margin account
        marginAccount.unlockMargin(msg.sender, params.amount);

        emit MarginRemoved(msg.sender, params.tokenId, params.amount);
    }

    /*//////////////////////////////////////////////////////////////
                        MARGIN ACCOUNT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit USDC into margin account
    /// @param amount Amount to deposit
    function depositMargin(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be positive");
        
        USDC.safeTransferFrom(msg.sender, address(marginAccount), amount);
        
        // Note: User can directly call marginAccount.deposit() if they prefer
        // This function is for convenience
    }

    /// @notice Withdraw USDC from margin account
    /// @param amount Amount to withdraw
    function withdrawMargin(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be positive");
        
        // Note: User should call marginAccount.withdraw() directly
        // This would require additional authorization setup
        marginAccount.unlockMargin(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get position details with current PnL
    /// @param tokenId Position token ID
    /// @return position Position data
    /// @return unrealizedPnL Unrealized profit/loss
    /// @return currentPrice Current mark price
    /// @return liquidationPrice Estimated liquidation price
    function getPositionWithPnL(uint256 tokenId) external view returns (
        PositionLib.Position memory position,
        int256 unrealizedPnL,
        uint256 currentPrice,
        uint256 liquidationPrice
    ) {
        position = positionManager.getPosition(tokenId);
        
        PoolId poolId = PoolId.wrap(position.marketId);
        currentPrice = fundingOracle.getMarkPrice(poolId);
        
        unrealizedPnL = positionManager.getUnrealizedPnL(tokenId, currentPrice);
        liquidationPrice = _calculateLiquidationPrice(position);
    }

    /// @notice Calculate required margin for a position
    /// @param marginAmount Margin amount
    /// @param leverage Desired leverage
    /// @param price Current price
    /// @return notionalSize Position notional size
    /// @return baseSize Position size in base asset
    function calculatePositionSize(
        uint256 marginAmount,
        uint256 leverage,
        uint256 price
    ) external pure returns (uint256 notionalSize, uint256 baseSize) {
        notionalSize = (marginAmount * 1e12 * leverage) / 1e18;
        baseSize = (notionalSize * 1e18) / price;
    }

    /// @notice Get user's total margin account balance
    /// @param user User address
    /// @return Total balance (free + locked)
    function getUserBalance(address user) external view returns (uint256) {
        return marginAccount.getTotalBalance(user);
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Validate open position parameters
    function _validateOpenParams(OpenPositionParams calldata params) internal view {
        if (params.leverage == 0 || params.leverage > MAX_LEVERAGE * 1e18) {
            revert InvalidLeverage();
        }
        if (params.slippageBps > MAX_SLIPPAGE_BPS) {
            revert InvalidSlippage();
        }
        if (params.marginAmount == 0) {
            revert InsufficientMargin();
        }
    }

    /// @notice Validate close position parameters
    function _validateCloseParams(ClosePositionParams calldata params) internal pure {
        if (params.sizeBps == 0 || params.sizeBps > BPS_DENOMINATOR) {
            revert InvalidCloseSize();
        }
        if (params.slippageBps > MAX_SLIPPAGE_BPS) {
            revert InvalidSlippage();
        }
    }

    /// @notice Calculate partial PnL for position closing
    function _calculatePartialPnL(
        PositionLib.Position memory position,
        uint256 currentPrice,
        uint256 sizeBps
    ) internal pure returns (int256) {
        if (position.sizeBase == 0) return 0;
        
        // Calculate PnL for the full position first
        int256 priceDiff = int256(currentPrice) - int256(position.entryPrice);
        int256 fullPnL = (position.sizeBase * priceDiff) / int256(1e18);
        
        // Convert to 6 decimals for USDC
        fullPnL = fullPnL / 1e12;
        
        // Return proportional PnL
        return (fullPnL * int256(sizeBps)) / int256(BPS_DENOMINATOR);
    }

    /// @notice Calculate liquidation price for a position
    function _calculateLiquidationPrice(PositionLib.Position memory position) 
        internal 
        pure 
        returns (uint256) 
    {
        if (position.sizeBase == 0) return 0;
        
        // Simplified liquidation price calculation
        // Actual implementation would need maintenance margin ratio
        uint256 maintenanceMarginRatio = 500; // 5% maintenance margin
        uint256 notionalValue = uint256(position.sizeBase > 0 ? position.sizeBase : -position.sizeBase) * position.entryPrice / 1e18;
        uint256 maintenanceMargin = (notionalValue * maintenanceMarginRatio) / BPS_DENOMINATOR;
        
        if (position.sizeBase > 0) {
            // Long position - liquidated when price drops
            uint256 maxLoss = position.margin * 1e12 - maintenanceMargin; // Convert USDC to 18 decimals
            return position.entryPrice - (maxLoss * 1e18) / uint256(position.sizeBase);
        } else {
            // Short position - liquidated when price rises  
            uint256 maxLoss = position.margin * 1e12 - maintenanceMargin;
            return position.entryPrice + (maxLoss * 1e18) / uint256(-position.sizeBase);
        }
    }

    /// @notice Reduce position size (placeholder - would need PositionManager support)
    function _reducePosition(address user, uint256 tokenId, uint256 sizeToReduce, uint256 marginToRelease) internal {
        // Get current position
        PositionLib.Position memory position = positionManager.getPosition(tokenId);
        
        // Calculate new size and margin
        bool isLong = position.sizeBase > 0;
        uint256 currentAbsoluteSize = uint256(isLong ? position.sizeBase : -position.sizeBase);
        uint256 newAbsoluteSize = currentAbsoluteSize - sizeToReduce;
        int256 newSizeBase = isLong ? int256(newAbsoluteSize) : -int256(newAbsoluteSize);
        uint256 newMargin = position.margin - marginToRelease;
        
        // Update the position
        bool success = positionManager.updatePositionFor(user, tokenId, newSizeBase, newMargin);
        require(success, "Failed to update position");
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emergency function to recover accidentally sent tokens
    /// @param token Token address
    /// @param amount Amount to recover
    function emergencyRecover(address token, uint256 amount) external {
        require(token != address(USDC), "Cannot recover USDC");
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}
