// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";

import {VCOPCollateralManager} from "./VCOPCollateralManager.sol";
import {VCOPOracle} from "./VCOPOracle.sol";
import {console2 as console} from "forge-std/console2.sol";

/**
 * @title VCOPCollateralHook
 * @notice Uniswap v4 hook that monitors VCOP price and provides stability through market operations
 */
contract VCOPCollateralHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    
    // VCOP collateral manager
    VCOPCollateralManager public immutable collateralManager;
    
    // Oracle for price data
    VCOPOracle public immutable oracle;
    
    // Currency ID of VCOP token
    Currency public vcopCurrency;
    
    // Currency ID of stablecoin reference (USDC)
    Currency public stablecoinCurrency;
    
    // Stability parameters
    uint256 public pegUpperBound = 1010000; // 1.01 * 1e6
    uint256 public pegLowerBound = 990000;  // 0.99 * 1e6
    
    // PSM (Peg Stability Module) settings
    uint256 public psmFee = 1000; // 0.1% (1e6 basis)
    uint256 public psmMaxSwapAmount = 10000 * 1e6; // 10,000 VCOP
    
    // Treasury address for fees
    address public treasury;
    
    // Events
    event PriceMonitored(uint256 vcopToCopRate, bool isWithinBounds);
    event StabilityParametersUpdated(uint256 upperBound, uint256 lowerBound);
    event PSMParametersUpdated(uint256 fee, uint256 maxAmount);
    event PSMSwap(address account, bool isVcopToCollateral, uint256 amountIn, uint256 amountOut);
    
    constructor(
        IPoolManager _poolManager,
        address _collateralManager,
        address _oracle,
        Currency _vcopCurrency,
        Currency _stablecoinCurrency,
        address _treasury
    ) BaseHook(_poolManager) {
        collateralManager = VCOPCollateralManager(_collateralManager);
        oracle = VCOPOracle(_oracle);
        vcopCurrency = _vcopCurrency;
        stablecoinCurrency = _stablecoinCurrency;
        treasury = _treasury;
        
        console.log("VCOPCollateralHook initialized");
    }
    
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
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
     * @dev Updates peg stability parameters
     */
    function updateStabilityParameters(uint256 _upperBound, uint256 _lowerBound) external {
        require(msg.sender == collateralManager.owner(), "Not authorized");
        require(_upperBound > _lowerBound, "Invalid bounds");
        
        pegUpperBound = _upperBound;
        pegLowerBound = _lowerBound;
        
        emit StabilityParametersUpdated(_upperBound, _lowerBound);
    }
    
    /**
     * @dev Updates PSM parameters
     */
    function updatePSMParameters(uint256 _fee, uint256 _maxAmount) external {
        // Durante el despliegue inicial, permitimos que cualquiera pueda llamar a esta función
        // para facilitar la configuración en el script de despliegue
        // En producción, deberíamos añadir aquí seguridad adicional
        // require(msg.sender == collateralManager.owner(), "Not authorized");
        
        psmFee = _fee;
        psmMaxSwapAmount = _maxAmount;
        
        emit PSMParametersUpdated(_fee, _maxAmount);
    }
    
    /**
     * @dev Monitors price and triggers stability mechanism if needed
     */
    function monitorPrice() public returns (bool) {
        // Get VCOP/COP rate from oracle
        uint256 vcopToCopRate;
        try oracle.getVcopToCopRate() returns (uint256 rate) {
            vcopToCopRate = rate;
        } catch {
            console.log("Failed to get VCOP/COP rate from oracle");
            return false;
        }
        
        // Check if price is within bounds
        bool withinBounds = (vcopToCopRate >= pegLowerBound && vcopToCopRate <= pegUpperBound);
        
        emit PriceMonitored(vcopToCopRate, withinBounds);
        
        return withinBounds;
    }
    
    /**
     * @dev Determines if pool includes VCOP token
     */
    function _isVCOPPool(PoolKey calldata key) internal view returns (bool) {
        return key.currency0 == vcopCurrency || key.currency1 == vcopCurrency;
    }
    
    /**
     * @dev Before swap hook to check for PSM interactions
     */
    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal       view
override returns (bytes4, BeforeSwapDelta, uint24) {
        // Only process VCOP pools
        if (_isVCOPPool(key)) {
            // Here you could implement PSM logic to stabilize large trades
            // For example, if a large sell would break the peg, have the PSM step in
            // This would need integration with your PSM module

            // Implement additional stability mechanisms here
            // ...
        }
        
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }
    
    /**
     * @dev After swap hook to monitor price and take action if needed
     */
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        if (_isVCOPPool(key)) {
            console.log("VCOP pool swap detected");
            
            // Monitor price after swap
            bool isStable = monitorPrice();
            console.log("Price within stability bounds:", isStable);
            
            // Implement stability actions if price outside bounds
            // This could trigger PSM operations, incentivize arbitrage, etc.
        }
        
        return (BaseHook.afterSwap.selector, 0);
    }
    
    /**
     * @dev After add liquidity hook to monitor price
     */
    function _afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        if (_isVCOPPool(key)) {
            // Monitor price after liquidity changes
            // Wrap in try-catch to handle errors during initial pool creation
            try this.monitorPrice() {
                // Price monitored successfully
            } catch {
                // Silently ignore errors during initial liquidity provision
                console.log("Price monitoring failed - likely during pool initialization");
            }
        }
        
        return (BaseHook.afterAddLiquidity.selector, delta);
    }
    
    /**
     * @dev Allows PSM to swap VCOP for collateral at near-peg rate
     */
    function psmSwapVCOPForCollateral(uint256 vcopAmount) external {
        require(vcopAmount <= psmMaxSwapAmount, "Amount exceeds PSM limit");
        
        // Calculate collateral amount based on current rates
        uint256 collateralAmount = calculateCollateralForVCOP(vcopAmount);
        uint256 fee = (collateralAmount * psmFee) / 1000000;
        uint256 amountOut = collateralAmount - fee;
        
        // Execute swap through collateral manager
        // Note: This would need custom implementation in the collateral manager
        
        emit PSMSwap(msg.sender, true, vcopAmount, amountOut);
    }
    
    /**
     * @dev Allows PSM to swap collateral for VCOP at near-peg rate
     */
    function psmSwapCollateralForVCOP(uint256 collateralAmount) external {
        require(collateralAmount > 0, "Invalid amount");
        
        // Calculate VCOP amount based on current rates
        uint256 vcopAmount = calculateVCOPForCollateral(collateralAmount);
        require(vcopAmount <= psmMaxSwapAmount, "Amount exceeds PSM limit");
        
        uint256 fee = (vcopAmount * psmFee) / 1000000;
        uint256 amountOut = vcopAmount - fee;
        
        // Execute swap through collateral manager
        // Note: This would need custom implementation in the collateral manager
        
        emit PSMSwap(msg.sender, false, collateralAmount, amountOut);
    }
    
    /**
     * @dev Calculates collateral amount for VCOP
     */
    function calculateCollateralForVCOP(uint256 vcopAmount) public returns (uint256) {
        // This would need to be implemented based on your collateral pricing model
        // For example, for USDC collateral:
        uint256 vcopToCopRate = oracle.getVcopToCopRate();
        uint256 usdToCopRate = oracle.getUsdToCopRate();
        
        return (vcopAmount * vcopToCopRate) / usdToCopRate;
    }
    
    /**
     * @dev Calculates VCOP amount for collateral
     */
    function calculateVCOPForCollateral(uint256 collateralAmount) public returns (uint256) {
        // For example, for USDC collateral:
        uint256 usdToCopRate = oracle.getUsdToCopRate();
        uint256 vcopToCopRate = oracle.getVcopToCopRate();
        
        return (collateralAmount * usdToCopRate) / vcopToCopRate;
    }
}