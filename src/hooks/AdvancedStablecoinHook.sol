// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IOracle.sol";
import "../AlgorithmicStablecoin.sol";

/**
 * @title AdvancedStablecoinHook
 * @notice An advanced hook for algorithmic stablecoins that combines fee adjustments and liquidity management
 */
contract AdvancedStablecoinHook is BaseHook, Ownable {
    using PoolIdLibrary for PoolKey;
    using SafeERC20 for IERC20;

    // Price thresholds for intervention (with 18 decimals)
    uint256 public upperPriceThreshold = 1.05e18; // 1.05 COP
    uint256 public lowerPriceThreshold = 0.97e18; // 0.97 COP
    
    // Extreme price thresholds that trigger rebase
    uint256 public extremeUpperThreshold = 1.10e18; // 1.10 COP
    uint256 public extremeLowerThreshold = 0.90e18; // 0.90 COP
    
    // Stabilization fee parameters
    uint24 public baseFee = 3000; // 0.3% (same as original pool fee)
    uint24 public maxStabilizationFee = 10000; // 1% maximum additional fee
    
    // Reference to oracle for price data
    IOracle public oracle;
    
    // Reference to stablecoin to allow rebasing in extreme cases
    AlgorithmicStablecoin public stablecoin;
    
    // Tracking for rebase epochs
    uint256 public lastRebaseTime;
    uint256 public rebaseCooldown = 1 days;
    uint256 public currentEpoch;
    
    // Tracking for fee adjustments
    uint256 public lastFeeAdjustmentTime;
    uint256 public feeAdjustmentCooldown = 1 hours;
    
    // Mapping to track which pools this hook is authorized to manage
    mapping(PoolId => bool) public authorizedPools;
    
    // Keep track of which token is the stablecoin in each pool
    mapping(PoolId => bool) public stablecoinIsToken0;
    
    // Track active fee adjustments per pool
    mapping(PoolId => uint24) public currentExtraFees;
    
    // Liquidity management reserves
    uint256 public reserveToken0;
    uint256 public reserveToken1;
    bool public liquidityManagementEnabled;
    
    // Events
    event PriceStabilizationTriggered(PoolId indexed poolId, uint256 currentPrice, uint24 newFee);
    event PoolAuthorized(PoolId indexed poolId, bool stablecoinIsToken0);
    event ThresholdsUpdated(uint256 lowerThreshold, uint256 upperThreshold);
    event OracleUpdated(address newOracle);
    event RebaseTriggered(uint256 indexed epoch, int256 supplyDelta);
    event LiquidityAdded(PoolId indexed poolId, int24 tickLower, int24 tickUpper, uint128 amount);
    event LiquidityRemoved(PoolId indexed poolId, int24 tickLower, int24 tickUpper, uint128 amount);

    constructor(
        IPoolManager _poolManager,
        IOracle _oracle,
        AlgorithmicStablecoin _stablecoin
    ) BaseHook(_poolManager) Ownable(msg.sender) {
        oracle = _oracle;
        stablecoin = _stablecoin;
        lastRebaseTime = block.timestamp;
        lastFeeAdjustmentTime = block.timestamp;
    }

    /**
     * @notice Define hook permissions
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: true,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /**
     * @notice Authorize a pool to be managed by this hook
     * @param key The pool key
     * @param isToken0 Whether the stablecoin is token0 in the pool
     */
    function authorizePool(PoolKey calldata key, bool isToken0) external onlyOwner {
        PoolId poolId = key.toId();
        authorizedPools[poolId] = true;
        stablecoinIsToken0[poolId] = isToken0;
        emit PoolAuthorized(poolId, isToken0);
    }

    /**
     * @notice Update price thresholds
     * @param lower New lower threshold (scaled by 1e18)
     * @param upper New upper threshold (scaled by 1e18)
     * @param extremeLower New extreme lower threshold (scaled by 1e18)
     * @param extremeUpper New extreme upper threshold (scaled by 1e18)
     */
    function updateThresholds(
        uint256 lower,
        uint256 upper,
        uint256 extremeLower,
        uint256 extremeUpper
    ) external onlyOwner {
        require(lower < upper && extremeLower < lower && upper < extremeUpper, "Invalid thresholds");
        lowerPriceThreshold = lower;
        upperPriceThreshold = upper;
        extremeLowerThreshold = extremeLower;
        extremeUpperThreshold = extremeUpper;
        emit ThresholdsUpdated(lower, upper);
    }

    /**
     * @notice Enable liquidity management
     * @param enabled Whether to enable liquidity management
     */
    function setLiquidityManagement(bool enabled) external onlyOwner {
        liquidityManagementEnabled = enabled;
    }

    /**
     * @notice Update the oracle contract
     * @param _oracle New oracle address
     */
    function setOracle(IOracle _oracle) external onlyOwner {
        oracle = _oracle;
        emit OracleUpdated(address(_oracle));
    }

    /**
     * @notice Deposit tokens for liquidity management
     * @param token0 Token0 address
     * @param token1 Token1 address
     * @param amount0 Amount of token0
     * @param amount1 Amount of token1
     */
    function depositReserves(address token0, address token1, uint256 amount0, uint256 amount1) external onlyOwner {
        if (amount0 > 0) {
            IERC20(token0).safeTransferFrom(msg.sender, address(this), amount0);
            reserveToken0 += amount0;
        }
        
        if (amount1 > 0) {
            IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1);
            reserveToken1 += amount1;
        }
    }

    /**
     * @notice Withdraw tokens from liquidity management reserves
     * @param token0 Token0 address
     * @param token1 Token1 address
     * @param amount0 Amount of token0
     * @param amount1 Amount of token1
     */
    function withdrawReserves(address token0, address token1, uint256 amount0, uint256 amount1) external onlyOwner {
        if (amount0 > 0 && amount0 <= reserveToken0) {
            IERC20(token0).safeTransfer(msg.sender, amount0);
            reserveToken0 -= amount0;
        }
        
        if (amount1 > 0 && amount1 <= reserveToken1) {
            IERC20(token1).safeTransfer(msg.sender, amount1);
            reserveToken1 -= amount1;
        }
    }

    /**
     * @notice After pool initialization setup
     */
    function _afterInitialize(address, PoolKey calldata /* key_ */, uint160, int24, bytes calldata)
        internal
        pure
        returns (bytes4)
    {
        // Simply return the selector, actual authorization is done via authorizePool
        return BaseHook.afterInitialize.selector;
    }

    /**
     * @notice Before a swap, check if we need to adjust fees for stability
     */
    function _beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolId poolId = key.toId();
        
        // Only act on authorized pools
        if (!authorizedPools[poolId]) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        // Get current price from oracle
        uint256 oraclePrice = oracle.getPrice();
        
        // Check for extreme price deviation that requires rebase
        if (shouldRebase(oraclePrice)) {
            triggerRebase(oraclePrice);
        }

        // Check if we should adjust fees based on cooldown
        if (block.timestamp >= lastFeeAdjustmentTime + feeAdjustmentCooldown) {
            uint24 stabilizationFee = calculateDynamicFee(poolId, params, oraclePrice);
            
            if (stabilizationFee > 0) {
                lastFeeAdjustmentTime = block.timestamp;
                currentExtraFees[poolId] = stabilizationFee;
                emit PriceStabilizationTriggered(poolId, oraclePrice, stabilizationFee);
            }
            
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, stabilizationFee);
        }
        
        // Return current fee adjustment if within cooldown period
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, currentExtraFees[poolId]);
    }

    /**
     * @notice Calculate dynamic fee based on price deviation
     */
    function calculateDynamicFee(
        PoolId poolId, 
        IPoolManager.SwapParams calldata params, 
        uint256 oraclePrice
    ) internal view returns (uint24) {
        uint24 stabilizationFee = 0;
        
        if (oraclePrice > upperPriceThreshold) {
            // Price is too high - increase fees for buying stablecoin
            bool buyingStablecoin = params.zeroForOne == stablecoinIsToken0[poolId];
            
            if (buyingStablecoin) {
                // Scale fee based on deviation from target
                uint256 deviation = oraclePrice - 1e18;
                uint256 maxDeviation = upperPriceThreshold - 1e18;
                stabilizationFee = uint24((deviation * maxStabilizationFee) / maxDeviation);
                
                // Cap at maximum fee
                if (stabilizationFee > maxStabilizationFee) {
                    stabilizationFee = maxStabilizationFee;
                }
            }
        } else if (oraclePrice < lowerPriceThreshold) {
            // Price is too low - increase fees for selling stablecoin
            bool sellingStablecoin = params.zeroForOne != stablecoinIsToken0[poolId];
            
            if (sellingStablecoin) {
                // Scale fee based on deviation from target
                uint256 deviation = 1e18 - oraclePrice;
                uint256 maxDeviation = 1e18 - lowerPriceThreshold;
                stabilizationFee = uint24((deviation * maxStabilizationFee) / maxDeviation);
                
                // Cap at maximum fee
                if (stabilizationFee > maxStabilizationFee) {
                    stabilizationFee = maxStabilizationFee;
                }
            }
        }
        
        return stabilizationFee;
    }

    /**
     * @notice Check if conditions warrant a rebase
     */
    function shouldRebase(uint256 price) internal view returns (bool) {
        // Only rebase if cooldown period has passed
        if (block.timestamp < lastRebaseTime + rebaseCooldown) {
            return false;
        }
        
        // Rebase if price is outside extreme thresholds
        return price > extremeUpperThreshold || price < extremeLowerThreshold;
    }

    /**
     * @notice Trigger a rebase based on price deviation
     */
    function triggerRebase(uint256 price) internal {
        // Calculate supply delta based on price deviation
        int256 supplyDelta;
        uint256 totalSupply = stablecoin.totalSupply();
        
        if (price > extremeUpperThreshold) {
            // If price is too high, increase supply by 2%
            supplyDelta = int256(totalSupply * 2 / 100);
        } else if (price < extremeLowerThreshold) {
            // If price is too low, decrease supply by 2%
            supplyDelta = -int256(totalSupply * 2 / 100);
        } else {
            return; // No rebase needed
        }
        
        // Update tracking
        currentEpoch++;
        lastRebaseTime = block.timestamp;
        
        // Execute rebase
        stablecoin.rebase(currentEpoch, supplyDelta);
        
        emit RebaseTriggered(currentEpoch, supplyDelta);
    }
    
    /**
     * @notice Manual rebase function (emergency only)
     */
    function manualRebase(int256 supplyDelta) external onlyOwner {
        currentEpoch++;
        lastRebaseTime = block.timestamp;
        stablecoin.rebase(currentEpoch, supplyDelta);
        emit RebaseTriggered(currentEpoch, supplyDelta);
    }

    /**
     * @notice After a swap, analyze the impact and potentially rebalance liquidity
     */
    function _afterSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, BalanceDelta delta, bytes calldata)
        internal
        view
        override
        returns (bytes4, int128)
    {
        // If liquidity management is enabled, consider rebalancing after significant swaps
        if (liquidityManagementEnabled) {
            // Check if this was a significant swap that might need rebalancing
            if (delta.amount0() > 0 || delta.amount1() > 0) {
                // Future enhancement: Trigger liquidity rebalancing based on swap size and direction
            }
        }
        
        return (BaseHook.afterSwap.selector, 0);
    }

    /**
     * @notice Before adding liquidity, verify and potentially guide the position
     */
    function _beforeAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata /* params */,
        bytes calldata
    ) internal       view
override returns (bytes4) {
        PoolId poolId = key.toId();
        
        // Only check authorized pools
        if (authorizedPools[poolId]) {
            // Future enhancement: Guide liquidity positions to concentrate around target price
        }
        
        return BaseHook.beforeAddLiquidity.selector;
    }

    /**
     * @notice After liquidity addition, track the change
     */
    function _afterAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta,  // feesAccrued (unused)
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        PoolId poolId = key.toId();
        
        if (authorizedPools[poolId] && params.liquidityDelta > 0) {
            // We need to safely convert liquidityDelta (int256) to uint128
            // First ensure it's positive, then cast safely to avoid truncation issues
            uint256 liquidityDeltaUint = params.liquidityDelta > 0 ? uint256(params.liquidityDelta) : 0;
            // Then ensure it doesn't exceed uint128 max value
            uint128 liquidityDeltaUint128 = liquidityDeltaUint > type(uint128).max ? type(uint128).max : uint128(liquidityDeltaUint);
            
            emit LiquidityAdded(poolId, params.tickLower, params.tickUpper, liquidityDeltaUint128);
        }
        
        return (BaseHook.afterAddLiquidity.selector, delta);
    }

    /**
     * @notice Before removing liquidity
     */
    function _beforeRemoveLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata
    ) internal override returns (bytes4) {
        PoolId poolId = key.toId();
        
        if (authorizedPools[poolId] && params.liquidityDelta < 0) {
            // We need to safely convert liquidityDelta (int256) to uint128
            // First ensure it's negative, make it positive, then cast safely to avoid truncation issues
            uint256 liquidityDeltaUint = params.liquidityDelta < 0 ? uint256(-params.liquidityDelta) : 0;
            // Then ensure it doesn't exceed uint128 max value
            uint128 liquidityDeltaUint128 = liquidityDeltaUint > type(uint128).max ? type(uint128).max : uint128(liquidityDeltaUint);
            
            emit LiquidityRemoved(poolId, params.tickLower, params.tickUpper, liquidityDeltaUint128);
        }
        
        return BaseHook.beforeRemoveLiquidity.selector;
    }
} 