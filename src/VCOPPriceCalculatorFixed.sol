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
 * @title VCOPPriceCalculatorFixed
 * @notice Versión mejorada del calculador de precios con manejo robusto de errores
 */
contract VCOPPriceCalculatorFixed {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;

    // Pool Manager de Uniswap v4
    IPoolManager public immutable poolManager;
    
    // Direcciones de los tokens para la pool
    address public immutable vcopAddress;
    address public immutable usdcAddress;
    
    // Parámetros del pool
    uint24 public immutable fee;
    int24 public immutable tickSpacing;
    address public immutable hookAddress;
    
    // Tasa USD-COP (1 USD = 4200 COP)
    uint256 public immutable usdToCopRate;
    
    // Indica si VCOP es token0 en el pool
    bool public isVCOPToken0;
    
    // Valor por defecto para usar cuando no hay precio disponible
    uint256 public constant DEFAULT_VCOP_USD_PRICE = 4022000000; // 4022 VCOP por 1 USD
    
    // Eventos para seguimiento
    event PriceCalculated(uint256 sqrtPriceX96, int24 tick, uint256 vcopToUsdPrice, uint256 vcopToCopPrice);
    event PriceCalculationError(string errorType, string errorMessage);

    /**
     * @dev Constructor que inicializa el calculador con la configuración del pool
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
        
        // Determinar si VCOP es token0 o token1 (ordenamiento lexicográfico)
        isVCOPToken0 = uint160(_vcopAddress) < uint160(_usdcAddress);
        
        // Log valores relevantes al inicializar
        console.log("PriceCalculatorFixed iniciado. USD/COP rate:", _usdToCopRate);
        console.log("VCOP es token0:", isVCOPToken0);
    }
    
    /**
     * @dev Crea la estructura PoolKey para el pool VCOP-USDC
     */
    function createPoolKey() public view returns (PoolKey memory) {
        Currency currency0;
        Currency currency1;
        
        // Asignar tokens según el orden correcto
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
     * @dev Helper para manejar overflows en multiplicaciones
     */
    function safeMultiply(uint256 a, uint256 b) internal pure returns (uint256, bool) {
        // Check if the result would overflow
        if (a == 0 || b == 0) return (0, false);
        
        uint256 c = a * b;
        if (c / a != b) return (0, true); // overflow occurred
        
        return (c, false);
    }
    
    /**
     * @dev Helper para división segura
     */
    function safeDivide(uint256 a, uint256 b) internal pure returns (uint256, bool) {
        if (b == 0) return (0, true); // división por cero
        
        return (a / b, false);
    }
    
    /**
     * @dev Obtiene el precio VCOP/USDC desde el pool con mejor manejo de errores
     * @return Precio VCOP/USDC con 6 decimales, tick actual y un flag de error
     */
    function getVcopToUsdPriceFromPool() public view returns (uint256, int24, bool) {
        try this.getPoolData() returns (uint160 sqrtPriceX96, int24 tick, bool success) {
            // Si no pudimos obtener los datos del pool o sqrtPriceX96 es cero
            if (!success || sqrtPriceX96 == 0) {
                console.log("No se pudo obtener datos validos del pool, usando valor por defecto");
                return (DEFAULT_VCOP_USD_PRICE, 0, true);
            }
            
            // Calcular el precio base con protección contra overflow
            uint256 rawPrice;
            bool overflowed;
            
            // Cálculo de rawPrice = (sqrtPriceX96^2 * 1e18) >> 192
            // Primero: sqrtPriceX96^2
            (uint256 sqrtSquared, bool sqrtOverflow) = safeMultiply(uint256(sqrtPriceX96), uint256(sqrtPriceX96));
            if (sqrtOverflow) {
                console.log("Overflow al calcular sqrtPriceX96^2, usando valor por defecto");
                return (DEFAULT_VCOP_USD_PRICE, 0, true);
            }
            
            // Segundo: * 1e18 y luego >> 192
            (uint256 withPrecision, bool precisionOverflow) = safeMultiply(sqrtSquared, 1e18);
            if (precisionOverflow) {
                console.log("Overflow al aplicar precision, usando valor por defecto");
                return (DEFAULT_VCOP_USD_PRICE, 0, true);
            }
            
            // Aplicar el shift de 192 bits para obtener el precio real
            rawPrice = withPrecision >> 192;
            
            // Calcular precio VCOP/USDC
            uint256 vcopToUsdPrice;
            
            if (isVCOPToken0) {
                // Si VCOP es token0, precio = 1/rawPrice
                if (rawPrice > 0) {
                    (vcopToUsdPrice, overflowed) = safeDivide(1e36, rawPrice);
                    if (overflowed) {
                        console.log("Error al calcular precio inverso, usando valor por defecto");
                        return (DEFAULT_VCOP_USD_PRICE, 0, true);
                    }
                } else {
                    console.log("rawPrice es cero, usando valor por defecto");
                    return (DEFAULT_VCOP_USD_PRICE, 0, true);
                }
            } else {
                // Si VCOP es token1, precio = rawPrice
                vcopToUsdPrice = rawPrice;
            }
            
            // Ajustar a 6 decimales (como USDC)
            vcopToUsdPrice = vcopToUsdPrice / 1e12;
            
            console.log("VCOP/USD price calculado (6 decimales):", vcopToUsdPrice);
            console.log("Tick actual:", tick);
            
            return (vcopToUsdPrice, tick, false);
        } catch (bytes memory err) {
            console.log("Error al obtener datos del pool:");
            console.logBytes(err);
            return (DEFAULT_VCOP_USD_PRICE, 0, true);
        }
    }
    
    /**
     * @dev Función separada para obtener los datos del pool (para mejor manejo de errores)
     */
    function getPoolData() external view returns (uint160 sqrtPriceX96, int24 tick, bool success) {
        try this.tryGetPoolSlot0() returns (uint160 _sqrtPriceX96, int24 _tick) {
            return (_sqrtPriceX96, _tick, true);
        } catch {
            return (0, 0, false);
        }
    }
    
    /**
     * @dev Intenta obtener slot0 del pool
     */
    function tryGetPoolSlot0() external view returns (uint160, int24) {
        PoolKey memory poolKey = createPoolKey();
        PoolId poolId = poolKey.toId();
        
        (uint160 sqrtPriceX96, int24 tick, , ) = poolManager.getSlot0(poolId);
        return (sqrtPriceX96, tick);
    }
    
    /**
     * @dev Calcula el precio VCOP/COP usando el precio VCOP/USDC y la tasa USD/COP
     * @return Precio VCOP/COP con 6 decimales, tick actual y un flag de error
     */
    function getVcopToCopPrice() public view returns (uint256, int24, bool) {
        (uint256 vcopToUsdPrice, int24 tick, bool hasError) = getVcopToUsdPriceFromPool();
        
        // Si hubo error obteniendo el precio VCOP/USDC, usamos el valor por defecto
        if (hasError) {
            vcopToUsdPrice = DEFAULT_VCOP_USD_PRICE;
        }
        
        // Calcular precio VCOP/COP con proteccion contra errores
        uint256 vcopToCopPrice = 0;
        
        console.log("=========== CALCULO VCOP/COP ===========");
        console.log("USD/COP rate (6 decimales):", usdToCopRate);
        console.log("VCOP/USD price (6 decimales):", vcopToUsdPrice);
        
        if (vcopToUsdPrice > 0) {
            // Calcular: (usdToCopRate * 1e6) / vcopToUsdPrice
            uint256 numerador;
            bool overflowed;
            
            (numerador, overflowed) = safeMultiply(usdToCopRate, 1e6);
            if (overflowed) {
                console.log("Overflow al calcular numerador, usando valor por defecto");
                return (1e6, 0, true); // Valor predeterminado 1:1
            }
            
            console.log("Numerador (usdToCopRate * 1e6):", numerador);
            
            (vcopToCopPrice, overflowed) = safeDivide(numerador, vcopToUsdPrice);
            if (overflowed) {
                console.log("Division por cero al calcular VCOP/COP, usando valor por defecto");
                return (1e6, 0, true); // Valor predeterminado 1:1
            }
            
            console.log("VCOP/COP = numerador / vcopToUsdPrice =", vcopToCopPrice);
            
            // Mostrar el cálculo como decimal para verificar
            uint256 entero = vcopToCopPrice / 1e6;
            uint256 fraccion = vcopToCopPrice % 1e6;
            console.log("VCOP/COP como numero decimal:", entero, ".", fraccion);
        } else {
            console.log("ADVERTENCIA: vcopToUsdPrice es cero, usando valor predeterminado");
            vcopToCopPrice = 1e6; // 1:1 por defecto
        }
        
        // Verificar si está en paridad
        uint256 toleranceLower = 990000; // 0.99 * 1e6
        uint256 toleranceUpper = 1010000; // 1.01 * 1e6
        bool estaEnParidad = (vcopToCopPrice >= toleranceLower && vcopToCopPrice <= toleranceUpper);
        
        console.log("Tolerancia inferior:", toleranceLower);
        console.log("Tolerancia superior:", toleranceUpper);
        console.log("Esta en paridad?:", estaEnParidad);
        console.log("======================================");
        
        return (vcopToCopPrice, tick, hasError);
    }
    
    /**
     * @dev Calcula si el precio de VCOP está en paridad 1:1
     * @return true si el precio VCOP/COP está en 1:1 con un margen de tolerancia
     */
    function isVcopAtParity() external view returns (bool) {
        (uint256 vcopToCopPrice, , bool hasError) = getVcopToCopPrice();
        
        // Si hubo un error y usamos valor predeterminado, asumimos paridad verdadera
        if (hasError) {
            console.log("Error al calcular precio, asumiendo paridad verdadera");
            return true;
        }
        
        // 1e6 es la representacion de 1 COP con 6 decimales
        // Consideramos una tolerancia del 1%
        uint256 toleranceLower = 990000; // 0.99 * 1e6
        uint256 toleranceUpper = 1010000; // 1.01 * 1e6
        
        bool enParidad = (vcopToCopPrice >= toleranceLower && vcopToCopPrice <= toleranceUpper);
        console.log("VCOP/COP rate para verificar paridad:", vcopToCopPrice);
        console.log("Esta en paridad 1:1? (990000-1010000):", enParidad);
        
        return enParidad;
    }
    
    /**
     * @dev Calcula todos los precios relevantes para el oráculo
     * @return vcopToUsdPrice Precio VCOP/USDC con 6 decimales
     * @return vcopToCopPrice Precio VCOP/COP con 6 decimales
     * @return currentTick Tick actual del pool
     * @return isAtParity Indica si VCOP está en paridad 1:1 con COP
     */
    function calculateAllPrices() external view returns (
        uint256 vcopToUsdPrice,
        uint256 vcopToCopPrice,
        int24 currentTick,
        bool isAtParity
    ) {
        bool hasError;
        
        // Obtener precio VCOP/USDC
        (vcopToUsdPrice, currentTick, hasError) = getVcopToUsdPriceFromPool();
        
        // Usar valor por defecto si hay error
        if (hasError) {
            vcopToUsdPrice = DEFAULT_VCOP_USD_PRICE;
        }
        
        // Calcular VCOP/COP a partir de VCOP/USDC
        if (vcopToUsdPrice > 0) {
            bool divError;
            uint256 numerador = usdToCopRate * 1e6; // Esto no debería causar overflow con valores razonables
            (vcopToCopPrice, divError) = safeDivide(numerador, vcopToUsdPrice);
            
            if (divError) {
                vcopToCopPrice = 1e6; // Valor por defecto 1:1
            }
        } else {
            vcopToCopPrice = 1e6; // Valor por defecto 1:1
        }
        
        // Determinar si está en paridad
        uint256 toleranceLower = 990000; // 0.99 * 1e6
        uint256 toleranceUpper = 1010000; // 1.01 * 1e6
        isAtParity = (vcopToCopPrice >= toleranceLower && vcopToCopPrice <= toleranceUpper);
        
        // Logs detallados
        console.log("Resultados del calculo completo:");
        console.log("VCOP/USD price:", vcopToUsdPrice);
        console.log("VCOP/COP price:", vcopToCopPrice);
        console.log("Tick:", currentTick);
        console.log("En paridad?:", isAtParity);
        console.log("Hubo errores?:", hasError);
        
        return (vcopToUsdPrice, vcopToCopPrice, currentTick, isAtParity);
    }
} 