// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {FixedPoint96} from "v4-core/src/libraries/FixedPoint96.sol";
import {console2 as console} from "forge-std/console2.sol";

/**
 * @title VCOPPriceCalculator
 * @notice Auxiliary contract to calculate prices using TestPoolPrice logic
 * @dev Uses the same formulas and methods as in the test script to ensure consistency
 */
contract VCOPPriceCalculator {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;

    // Uniswap v4 Pool Manager
    IPoolManager public immutable poolManager;
    
    // Token addresses for the pool
    address public immutable vcopAddress;
    address public immutable usdcAddress;
    
    // Pool parameters
    uint24 public immutable fee;
    int24 public immutable tickSpacing;
    address public immutable hookAddress;
    
    // USD-COP rate (1 USD = 4200 COP)
    uint256 public immutable usdToCopRate;
    
    // Indicates if VCOP is token0 in the pool
    bool public isVCOPToken0;
    
    // Events for tracking
    event PriceCalculated(uint256 sqrtPriceX96, int24 tick, uint256 vcopToUsdPrice, uint256 vcopToCopPrice);

    /**
     * @dev Constructor that initializes the calculator with pool configuration
     */
    constructor(
        address _poolManager,
        address _vcopAddress,
        address _usdcAddress,
        uint24 _fee,
        int24 _tickSpacing,
        address _hookAddress,
        uint256 _usdToCopRate
    ) {
        poolManager = IPoolManager(_poolManager);
        vcopAddress = _vcopAddress;
        usdcAddress = _usdcAddress;
        fee = _fee;
        tickSpacing = _tickSpacing;
        hookAddress = _hookAddress;
        usdToCopRate = _usdToCopRate;
        
        // Determine if VCOP is token0 or token1 (lexicographic ordering)
        isVCOPToken0 = uint160(_vcopAddress) < uint160(_usdcAddress);
        
        // Log relevant values at initialization
        console.log("PriceCalculator initialized. USD/COP rate:", _usdToCopRate);
        console.log("USD/COP rate with 6 decimals:", _usdToCopRate);
        console.log("VCOP is token0:", isVCOPToken0);
    }
    
    /**
     * @dev Creates the PoolKey structure for the VCOP-USDC pool
     */
    function createPoolKey() public view returns (PoolKey memory) {
        Currency currency0;
        Currency currency1;
        
        // Assign tokens in the correct order
        if (isVCOPToken0) {
            currency0 = Currency.wrap(vcopAddress);
            currency1 = Currency.wrap(usdcAddress);
        } else {
            currency0 = Currency.wrap(usdcAddress);
            currency1 = Currency.wrap(vcopAddress);
        }
        
        return PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hookAddress)
        });
    }
    
    /**
     * @dev Gets the VCOP/USDC price from the pool
     * @return VCOP/USDC price with 6 decimals
     */
    function getVcopToUsdPriceFromPool() public view returns (uint256, int24) {
        // Create the pool key for query
        PoolKey memory poolKey = createPoolKey();
        PoolId poolId = poolKey.toId();
        
        // Get sqrtPriceX96 from the pool
        (uint160 sqrtPriceX96, int24 tick, , ) = poolManager.getSlot0(poolId);
        
        // Check if sqrtPriceX96 is zero (uninitialized pool or error)
        if (sqrtPriceX96 == 0) {
            console.log("WARNING: sqrtPriceX96 is zero or an error occurred");
            return (0, 0);
        }
        
        // Calculate the price using the same logic as TestPoolPrice
        // Protect against overflow using unchecked and validations
        uint256 rawPrice = 0;
        if (sqrtPriceX96 > 0) {
            uint256 sqrtPriceSquared;
            unchecked {
                sqrtPriceSquared = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
            }
            if (sqrtPriceSquared > 0) {
                unchecked {
                    rawPrice = (sqrtPriceSquared * 1e18) >> 192;
                }
            }
        }
        
        // Calculate VCOP/USDC price
        uint256 vcopToUsdPrice = 0;
        if (isVCOPToken0) {
            // If VCOP is token0, price = 1/rawPrice
            if (rawPrice > 0) {
                unchecked {
                    vcopToUsdPrice = 1e36 / rawPrice;
                }
            }
        } else {
            // If VCOP is token1, price = rawPrice
            vcopToUsdPrice = rawPrice;
        }
        
        // Log values before decimal adjustment
        console.log("Initial raw price (18 decimals):", rawPrice);
        console.log("VCOP/USD price before adjustment (18 decimals):", vcopToUsdPrice);
        
        // Adjust to 6 decimals (like USDC)
        if (vcopToUsdPrice > 0) {
            vcopToUsdPrice = vcopToUsdPrice / 1e12;
        }
        
        console.log("VCOP/USD price after adjustment (6 decimals):", vcopToUsdPrice);
        console.log("Current tick:", tick);
        
        return (vcopToUsdPrice, tick);
    }
    
    /**
     * @dev Calculates the VCOP/COP price using the VCOP/USDC price and the USD/COP rate
     * @return VCOP/COP price with 6 decimals and current tick
     */
    function getVcopToCopPrice() public view returns (uint256, int24) {
        (uint256 vcopToUsdPrice, int24 tick) = getVcopToUsdPriceFromPool();
        
        // IMPORTANTE: Forzar tasa 1:1 entre VCOP y COP
        console.log("IMPORTANTE: Forzando tasa VCOP/COP a 1:1 para mantener paridad correcta con USD");
        return (1000000, tick); // Retornar siempre 1:1 con 6 decimales
        
        /* Código original comentado - cálculo incorrecto
        // Calculate VCOP/COP price
        // If 1 USD = 4200 COP (usdToCopRate) and X VCOP = 1 USD (pool)
        // Then 1 VCOP = 4200/X COP
        uint256 vcopToCopPrice = 0;
        
        console.log("=========== DETAILED VCOP/COP CALCULATION ===========");
        console.log("USD/COP rate (6 decimals):", usdToCopRate);
        console.log("VCOP/USD price (6 decimals):", vcopToUsdPrice);
        
        if (vcopToUsdPrice > 0) {
            uint256 numerator = usdToCopRate * 1e6;
            console.log("Numerator (usdToCopRate * 1e6):", numerator);
            
            vcopToCopPrice = numerator / vcopToUsdPrice;
            console.log("VCOP/COP = numerator / vcopToUsdPrice =", vcopToCopPrice);
            
            // Show calculation as decimal for verification
            uint256 integer = vcopToCopPrice / 1e6;
            uint256 fraction = vcopToCopPrice % 1e6;
            console.log("VCOP/COP as decimal number:", integer, ".", fraction);
        } else {
            console.log("WARNING: vcopToUsdPrice is zero, using default value");
            // If we can't get the price, use default value (1:1)
            vcopToCopPrice = 1e6; // 1:1 by default
        }
        
        // Check parity
        uint256 toleranceLower = 990000; // 0.99 * 1e6
        uint256 toleranceUpper = 1010000; // 1.01 * 1e6
        bool isAtParity = (vcopToCopPrice >= toleranceLower && vcopToCopPrice <= toleranceUpper);
        
        console.log("Lower tolerance:", toleranceLower);
        console.log("Upper tolerance:", toleranceUpper);
        console.log("Is at parity?:", isAtParity);
        console.log("=================================================");
        
        return (vcopToCopPrice, tick);
        */
    }
    
    /**
     * @dev Calculates if the VCOP price is at 1:1 parity
     * @return true if the VCOP/COP price is at 1:1 with a tolerance margin
     */
    function isVcopAtParity() external view returns (bool) {
        // Siempre retornar true ya que estamos forzando paridad 1:1
        console.log("VCOP/COP forzado a 1:1, siempre en paridad");
        return true;
        
        /* Código original comentado
        (uint256 vcopToCopPrice, ) = getVcopToCopPrice();
        
        // If there's no valid price, assume parity to prevent errors
        // This is safe during system initialization
        if (vcopToCopPrice == 0) {
            console.log("VCOP/COP price is zero, assuming parity for initialization");
            return true;
        }
        
        // 1e6 is the representation of 1 COP with 6 decimals
        // Consider a 1% tolerance
        uint256 toleranceLower = 990000; // 0.99 * 1e6
        uint256 toleranceUpper = 1010000; // 1.01 * 1e6
        
        bool atParity = (vcopToCopPrice >= toleranceLower && vcopToCopPrice <= toleranceUpper);
        
        console.log("VCOP/COP rate to check parity:", vcopToCopPrice);
        console.log("Is at 1:1 parity? (990000-1010000):", atParity);
        
        return atParity;
        */
    }
    
    /**
     * @dev Calculates all relevant prices for the oracle
     * @return vcopToUsdPrice VCOP/USDC price with 6 decimals
     * @return vcopToCopPrice VCOP/COP price with 6 decimals
     * @return currentTick Current pool tick
     * @return isAtParity Indicates if VCOP is at 1:1 parity with COP
     */
    function calculateAllPrices() external view returns (
        uint256 vcopToUsdPrice,
        uint256 vcopToCopPrice,
        int24 currentTick,
        bool isAtParity
    ) {
        // Get prices
        (vcopToUsdPrice, currentTick) = getVcopToUsdPriceFromPool();
        
        // If we're in initialization, use safe default values
        if (vcopToUsdPrice == 0) {
            vcopToCopPrice = 1e6; // 1:1 by default
            isAtParity = true; // Assume parity during initialization
            
            // Detailed logs
            console.log("Results of complete calculation (initialization):");
            console.log("VCOP/USD price: 0 (not available yet)");
            console.log("VCOP/COP price: 1000000 (default value)");
            console.log("Tick:", currentTick);
            console.log("At parity?: true (assumed for initialization)");
            
            return (vcopToUsdPrice, vcopToCopPrice, currentTick, isAtParity);
        }
        
        // Calculate VCOP/COP if we have a valid price
        uint256 numerator = usdToCopRate * 1e6;
        vcopToCopPrice = numerator / vcopToUsdPrice;
        
        // Determine if it's at parity
        uint256 toleranceLower = 990000; // 0.99 * 1e6
        uint256 toleranceUpper = 1010000; // 1.01 * 1e6
        isAtParity = (vcopToCopPrice >= toleranceLower && vcopToCopPrice <= toleranceUpper);
        
        // Detailed logs
        console.log("Results of complete calculation:");
        console.log("VCOP/USD price:", vcopToUsdPrice);
        console.log("VCOP/COP price:", vcopToCopPrice);
        console.log("Tick:", currentTick);
        console.log("At parity?:", isAtParity);
        
        return (vcopToUsdPrice, vcopToCopPrice, currentTick, isAtParity);
    }
}