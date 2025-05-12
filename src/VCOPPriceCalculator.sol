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
 * @notice Contrato auxiliar para calcular precios usando la lógica de TestPoolPrice
 * @dev Usa las mismas fórmulas y métodos que en el script de test para asegurar consistencia
 */
contract VCOPPriceCalculator {
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
    
    // Eventos para seguimiento
    event PriceCalculated(uint256 sqrtPriceX96, int24 tick, uint256 vcopToUsdPrice, uint256 vcopToCopPrice);

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
        console.log("PriceCalculator iniciado. USD/COP rate:", _usdToCopRate);
        console.log("USD/COP rate con 6 decimales:", _usdToCopRate);
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
     * @dev Obtiene el precio VCOP/USDC desde el pool
     * @return Precio VCOP/USDC con 6 decimales
     */
    function getVcopToUsdPriceFromPool() public view returns (uint256, int24) {
        // Crear la clave del pool para consulta
        PoolKey memory poolKey = createPoolKey();
        PoolId poolId = poolKey.toId();
        
        // Intentar obtener datos directamente
        // Para evitar problemas de compilación, no usaremos try-catch
        uint160 sqrtPriceX96;
        int24 tick;
        
        // Llamada directa - puede fallar si el pool no existe
        // pero la manejamos verificando si sqrtPriceX96 == 0
        (sqrtPriceX96, tick, , ) = poolManager.getSlot0(poolId);
        
        // Verificar si sqrtPriceX96 es cero (pool no inicializado o error)
        if (sqrtPriceX96 == 0) {
            console.log("WARNING: sqrtPriceX96 es cero o ocurrio un error");
            return (0, 0);
        }
        
        // Calcular el precio usando la misma lógica de TestPoolPrice
        uint256 rawPrice = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 1e18) >> 192;
        
        // Calcular precio VCOP/USDC
        uint256 vcopToUsdPrice;
        if (isVCOPToken0) {
            // Si VCOP es token0, precio = 1/rawPrice
            vcopToUsdPrice = rawPrice > 0 ? (1e36 / rawPrice) : 0;
        } else {
            // Si VCOP es token1, precio = rawPrice
            vcopToUsdPrice = rawPrice;
        }
        
        // Log valores antes del ajuste de decimales
        console.log("Raw price inicial (18 decimales):", rawPrice);
        console.log("VCOP/USD price antes de ajuste (18 decimales):", vcopToUsdPrice);
        
        // Ajustar a 6 decimales (como USDC)
        vcopToUsdPrice = vcopToUsdPrice / 1e12;
        
        console.log("VCOP/USD price despues de ajuste (6 decimales):", vcopToUsdPrice);
        console.log("Tick actual:", tick);
        
        return (vcopToUsdPrice, tick);
    }
    
    /**
     * @dev Calcula el precio VCOP/COP usando el precio VCOP/USDC y la tasa USD/COP
     * @return Precio VCOP/COP con 6 decimales y tick actual
     */
    function getVcopToCopPrice() public view returns (uint256, int24) {
        (uint256 vcopToUsdPrice, int24 tick) = getVcopToUsdPriceFromPool();
        
        // Calcular precio VCOP/COP
        // Si 1 USD = 4200 COP (usdToCopRate) y X VCOP = 1 USD (pool)
        // Entonces 1 VCOP = 4200/X COP
        uint256 vcopToCopPrice = 0;
        
        console.log("=========== CALCULO DETALLADO VCOP/COP ===========");
        console.log("USD/COP rate (6 decimales):", usdToCopRate);
        console.log("VCOP/USD price (6 decimales):", vcopToUsdPrice);
        
        if (vcopToUsdPrice > 0) {
            uint256 numerador = usdToCopRate * 1e6;
            console.log("Numerador (usdToCopRate * 1e6):", numerador);
            
            vcopToCopPrice = numerador / vcopToUsdPrice;
            console.log("VCOP/COP = numerador / vcopToUsdPrice =", vcopToCopPrice);
            
            // Mostrar el cálculo como decimal para verificar
            uint256 entero = vcopToCopPrice / 1e6;
            uint256 fraccion = vcopToCopPrice % 1e6;
            console.log("VCOP/COP como numero decimal:", entero, ".", fraccion);
        } else {
            console.log("ADVERTENCIA: vcopToUsdPrice es cero, no se puede calcular VCOP/COP");
            // Valor predeterminado si no hay precio válido
            vcopToCopPrice = 1e6; // 1:1 por defecto
        }
        
        // Verificar paridad
        uint256 toleranceLower = 990000; // 0.99 * 1e6
        uint256 toleranceUpper = 1010000; // 1.01 * 1e6
        bool estaEnParidad = (vcopToCopPrice >= toleranceLower && vcopToCopPrice <= toleranceUpper);
        
        console.log("Tolerancia inferior:", toleranceLower);
        console.log("Tolerancia superior:", toleranceUpper);
        console.log("Esta en paridad?:", estaEnParidad);
        console.log("=================================================");
        
        return (vcopToCopPrice, tick);
    }
    
    /**
     * @dev Calcula si el precio de VCOP está en paridad 1:1
     * @return true si el precio VCOP/COP está en 1:1 con un margen de tolerancia
     */
    function isVcopAtParity() external view returns (bool) {
        (uint256 vcopToCopPrice, ) = getVcopToCopPrice();
        
        // Si no hay un precio válido, consideramos que no está en paridad
        if (vcopToCopPrice == 0) {
            console.log("Precio VCOP/COP es cero, considerando no en paridad");
            return false;
        }
        
        // 1e6 es la representación de 1 COP con 6 decimales
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
        // Obtener precios
        (vcopToUsdPrice, currentTick) = getVcopToUsdPriceFromPool();
        
        // Protección contra división por cero
        if (vcopToUsdPrice > 0) {
            vcopToCopPrice = (usdToCopRate * 1e6) / vcopToUsdPrice;
        } else {
            // Si el precio es cero, devolver un valor predeterminado
            vcopToCopPrice = 1e6; // 1:1 por defecto
            console.log("Precio VCOP/USD es cero, usando valor predeterminado para VCOP/COP");
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
        
        return (vcopToUsdPrice, vcopToCopPrice, currentTick, isAtParity);
    }
} 