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
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IOracle.sol";

/**
 * @title StablecoinHook
 * @notice A Uniswap v4 hook that implements price stability mechanisms for the VCOP stablecoin
 */
contract StablecoinHook is BaseHook, Ownable {
    using PoolIdLibrary for PoolKey;

    // Price thresholds for intervention (with 18 decimals)
    uint256 public upperPriceThreshold = 1.05e18; // 1.05 COP
    uint256 public lowerPriceThreshold = 0.97e18; // 0.97 COP
    
    // Stabilization fee parameters
    uint24 public baseFee = 3000; // 0.3% (same as original pool fee)
    uint24 public maxStabilizationFee = 10000; // 1% maximum additional fee

    // Reference to oracle for price data
    IOracle public oracle;
    
    // Tracking last intervention
    uint256 public lastInterventionTime;
    uint256 public interventionCooldown = 1 hours;
    
    // Mapping to track which pools this hook is authorized to manage
    mapping(PoolId => bool) public authorizedPools;
    
    // Keep track of which token is the stablecoin in each pool
    mapping(PoolId => bool) public stablecoinIsToken0;

    // Events
    event PriceStabilizationTriggered(PoolId indexed poolId, uint256 currentPrice, uint24 newFee);
    event PoolAuthorized(PoolId indexed poolId, bool stablecoinIsToken0);
    event ThresholdsUpdated(uint256 lowerThreshold, uint256 upperThreshold);
    event OracleUpdated(address newOracle);

    constructor(IPoolManager _poolManager, IOracle _oracle) BaseHook(_poolManager) Ownable(msg.sender) {
        oracle = _oracle;
        lastInterventionTime = block.timestamp;
    }

    /**
     * @notice Define hook permissions - we use beforeSwap, afterSwap and beforeAddLiquidity
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
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
     */
    function updateThresholds(uint256 lower, uint256 upper) external onlyOwner {
        require(lower < upper, "Invalid thresholds");
        lowerPriceThreshold = lower;
        upperPriceThreshold = upper;
        emit ThresholdsUpdated(lower, upper);
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
     * @notice After pool initialization, register it if authorized
     */
    function _afterInitialize(address, PoolKey calldata key, uint160, int24, bytes calldata)
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

        // Check if we should stabilize price based on cooldown
        if (block.timestamp < lastInterventionTime + interventionCooldown) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        // Get current price from oracle
        uint256 oraclePrice = oracle.getPrice();

        // Apply dynamic fee based on price deviation
        uint24 stabilizationFee = 0;
        
        if (oraclePrice > upperPriceThreshold) {
            // Price is too high - increase fees for buying stablecoin
            // (selling the paired token) to discourage demand
            bool buyingStablecoin = params.zeroForOne == stablecoinIsToken0[poolId];
            
            if (buyingStablecoin) {
                stabilizationFee = maxStabilizationFee;
                lastInterventionTime = block.timestamp;
                
                emit PriceStabilizationTriggered(poolId, oraclePrice, stabilizationFee);
            }
        } else if (oraclePrice < lowerPriceThreshold) {
            // Price is too low - increase fees for selling stablecoin
            // to discourage selling pressure
            bool sellingStablecoin = params.zeroForOne != stablecoinIsToken0[poolId];
            
            if (sellingStablecoin) {
                stabilizationFee = maxStabilizationFee;
                lastInterventionTime = block.timestamp;
                
                emit PriceStabilizationTriggered(poolId, oraclePrice, stabilizationFee);
            }
        }

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, stabilizationFee);
    }

    /**
     * @notice After a swap, monitor price changes
     */
    function _afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        pure
        override
        returns (bytes4, int128)
    {
        // Future enhancements could include analytics on price impact
        return (BaseHook.afterSwap.selector, 0);
    }

    /**
     * @notice Before adding liquidity, regulate concentration based on price
     */
    function _beforeAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata
    ) internal       pure
override returns (bytes4) {
        // Current implementation allows all liquidity additions
        // Future versions could regulate where liquidity can be added based on price stability
        return BaseHook.beforeAddLiquidity.selector;
    }
} 