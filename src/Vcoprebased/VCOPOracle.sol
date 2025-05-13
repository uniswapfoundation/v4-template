// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "v4-core/lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {console2 as console} from "forge-std/console2.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {VCOPPriceCalculator} from "./VCOPPriceCalculator.sol";

/**
 * @title VCOPOracle
 * @notice Oráculo para proveer precio de VCOP en relación al peso colombiano (COP) y dólar (USD)
 * @dev Usa 6 decimales para mantener consistencia con VCOP y USDC
 */
contract VCOPOracle is Ownable {
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
    
    // Indica si VCOP es token0 en el pool
    bool public isVCOPToken0;
    
    // Precio del dólar en pesos colombianos (con 6 decimales)
    // 4200 COP = 1 USD, entonces 4200 * 1e6 = 4.2e9
    uint256 private _usdToCopRate = 4200 * 1e6;
    
    // Factor de conversión VCOP a COP (con 6 decimales)
    // 1 VCOP = 1 COP inicialmente, entonces 1e6
    uint256 private _vcopToCopRate = 1e6;
    
    // Calculador de precios (implementación usando la lógica de TestPoolPrice)
    VCOPPriceCalculator public priceCalculator;

    // Eventos emitidos cuando se actualizan los precios
    event UsdToCopRateUpdated(uint256 oldRate, uint256 newRate);
    event VcopToCopRateUpdated(uint256 oldRate, uint256 newRate);
    
    // Nuevos eventos para seguimiento detallado
    event PriceRequested(address requester, string rateType);
    event PriceProvided(address requester, string rateType, uint256 rate);
    event PoolPriceUpdated(uint256 sqrtPriceX96, uint256 price);
    event PriceCalculatorSet(address calculator);

    /**
     * @dev Constructor que inicializa el oráculo con tasas iniciales y configuración del pool
     * @param initialUsdToCopRate La tasa inicial USD/COP (en formato 6 decimales)
     * @param _poolManager Dirección del PoolManager de Uniswap v4
     * @param _vcopAddress Dirección del token VCOP
     * @param _usdcAddress Dirección del token USDC
     * @param _fee Fee del pool (ej: 3000 para 0.3%)
     * @param _tickSpacing Espaciado de ticks del pool
     * @param _hookAddress Dirección del hook
     */
    constructor(
        uint256 initialUsdToCopRate,
        address _poolManager,
        address _vcopAddress,
        address _usdcAddress,
        uint24 _fee,
        int24 _tickSpacing,
        address _hookAddress
    ) Ownable(msg.sender) {
        if (initialUsdToCopRate > 0) {
            _usdToCopRate = initialUsdToCopRate;
        }
        
        poolManager = IPoolManager(_poolManager);
        vcopAddress = _vcopAddress;
        usdcAddress = _usdcAddress;
        fee = _fee;
        tickSpacing = _tickSpacing;
        hookAddress = _hookAddress;
        
        // Determinar si VCOP es token0 o token1 (ordenamiento lexicográfico)
        isVCOPToken0 = uint160(_vcopAddress) < uint160(_usdcAddress);
        
        console.log("VCOPOracle inicializado con Uniswap v4");
        console.log("Tasa inicial USD/COP:", _usdToCopRate);
        console.log("Tasa inicial VCOP/COP:", _vcopToCopRate);
        console.log("VCOP es token0:", isVCOPToken0);
    }
    
    /**
     * @dev Asigna el calculador de precios externo
     * @param _calculator Dirección del calculador de precios
     */
    function setPriceCalculator(address _calculator) external onlyOwner {
        require(_calculator != address(0), "Direccion del calculador no puede ser cero");
        priceCalculator = VCOPPriceCalculator(_calculator);
        emit PriceCalculatorSet(_calculator);
        
        console.log("Calculador de precios establecido:", _calculator);
    }
    
    /**
     * @dev Crea la estructura PoolKey para el pool VCOP-USDC
     */
    function _createPoolKey() internal view returns (PoolKey memory) {
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
     * @dev Obtiene el precio VCOP/USDC directamente del pool de Uniswap v4
     * @return El precio VCOP/USDC en formato de 6 decimales
     */
    function getVcopToUsdPriceFromPool() public view returns (uint256) {
        // Si tenemos el calculador de precios, usarlo
        if (address(priceCalculator) != address(0)) {
            (uint256 vcopToUsdPrice, ) = priceCalculator.getVcopToUsdPriceFromPool();
            console.log("ORACLE: Obtenido precio VCOP/USD via calculador:", vcopToUsdPrice);
            return vcopToUsdPrice;
        }
        
        // Implementación heredada como fallback
        PoolKey memory poolKey = _createPoolKey();
        PoolId poolId = poolKey.toId();
        
        // Obtener sqrtPriceX96 del pool
        (uint160 sqrtPriceX96, int24 tick, , ) = poolManager.getSlot0(poolId);
        console.log("ORACLE: sqrtPriceX96 del pool:", uint256(sqrtPriceX96));
        console.log("ORACLE: tick del pool:", tick);
        
        // Calcular precio a partir de sqrtPriceX96
        uint256 price;
        
        if (isVCOPToken0) {
            // Si VCOP es token0, el precio es 1/price (USDC/VCOP)
            price = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 1e6) >> 192;
            console.log("ORACLE: Precio intermedio (token0):", price);
            price = (1e12 * 1e6) / price; // Invertir y ajustar a 6 decimales (1e6)
        } else {
            // Si VCOP es token1, el precio es price (VCOP/USDC)
            price = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 1e6) >> 192;
            console.log("ORACLE: Precio intermedio (token1):", price);
        }
        
        console.log("ORACLE: Precio VCOP/USD calculado (6 decimales):", price);
        return price;
    }

    /**
     * @dev Actualiza las tasas de cambio basado en los precios reales del pool
     */
    function updateRatesFromPool() public returns (uint256, uint256) {
        // Obtener el precio VCOP/USDC del pool usando el calculador si está disponible
        uint256 vcopToUsdPrice;
        int24 currentTick;
        
        if (address(priceCalculator) != address(0)) {
            (vcopToUsdPrice, currentTick) = priceCalculator.getVcopToUsdPriceFromPool();
        } else {
            vcopToUsdPrice = getVcopToUsdPriceFromPool();
            currentTick = 0; // No podemos obtener el tick sin el calculador
        }
        
        console.log("========== ACTUALIZANDO TASAS ==========");
        console.log("Precio VCOP/USD del pool:", vcopToUsdPrice);
        console.log("Tasa USD/COP actual:", _usdToCopRate);
        
        // Cálculo simplificado de VCOP/COP
        // Si 1 USD = 4200 COP (tasa ideal) y tenemos X VCOP por 1 USDC (precio pool)
        // Entonces VCOP/COP = (1 USD / X VCOP) * (4200 COP / 1 USD) = 4200/X
        
        // Calcular VCOP/COP como la relación entre la tasa de referencia y la tasa actual
        // _usdToCopRate es el precio de 1 USD en COP (ej: 4200e6)
        // vcopToUsdPrice es el precio de 1 USDC en VCOP (ej: 4022e6)
        
        uint256 oldVcopToCopRate = _vcopToCopRate;
        
        // Si 1 USDC = 4022 VCOP y 1 USDC = 4200 COP, entonces:
        // 1 VCOP = (4200/4022) COP ≈ 1.04 COP
        if (vcopToUsdPrice > 0) {
            // Cálculo detallado con valores intermedios
            uint256 numerador = _usdToCopRate * 1e6;
            console.log("Numerador (_usdToCopRate * 1e6):", numerador);
            
            _vcopToCopRate = numerador / vcopToUsdPrice;
            console.log("VCOP/COP = numerador / vcopToUsdPrice =", _vcopToCopRate);
            
            // Mostrar el valor con decimales para verificación
            uint256 entero = _vcopToCopRate / 1e6;
            uint256 fraccion = _vcopToCopRate % 1e6;
            console.log("VCOP/COP como decimal:", entero, ".", fraccion);
        }
        
        console.log("Nueva tasa VCOP/COP calculada:", _vcopToCopRate);
        if (address(priceCalculator) != address(0)) {
            console.log("Tick actual:", currentTick);
        }
        
        // Verificar paridad
        bool estaEnParidad = isVcopAtParity();
        console.log("Esta en paridad 1:1?:", estaEnParidad);
        console.log("======================================");
        
        emit VcopToCopRateUpdated(oldVcopToCopRate, _vcopToCopRate);
        
        return (_vcopToCopRate, vcopToUsdPrice);
    }

    /**
     * @dev Verifica si el precio de VCOP está en paridad 1:1 con COP
     * @return true si el precio está en el rango de paridad
     */
    function isVcopAtParity() public view returns (bool) {
        // Mostrar el valor actual de VCOP/COP que se está evaluando
        console.log("Verificando paridad con VCOP/COP =", _vcopToCopRate);
        
        if (address(priceCalculator) != address(0)) {
            bool parityFromCalculator = priceCalculator.isVcopAtParity();
            console.log("Paridad segun calculador:", parityFromCalculator);
            return parityFromCalculator;
        }
        
        // Implementación fallback si no hay calculador
        // Se usa el último valor de _vcopToCopRate
        // 1e6 es la representación de 1 COP con 6 decimales
        // Consideramos una tolerancia del 1%
        uint256 toleranceLower = 990000; // 0.99 * 1e6
        uint256 toleranceUpper = 1010000; // 1.01 * 1e6
        
        bool enParidad = (_vcopToCopRate >= toleranceLower && _vcopToCopRate <= toleranceUpper);
        console.log("Tolerancia inferior:", toleranceLower);
        console.log("Tolerancia superior:", toleranceUpper);
        console.log("Esta en paridad? (fallback):", enParidad);
        
        return enParidad;
    }

    /**
     * @dev Obtiene la tasa de cambio USD a COP
     * @return La tasa en formato de 6 decimales (ej: 4200e6 para 4200 COP por 1 USD)
     */
    function getUsdToCopRate() external returns (uint256) {
        console.log("Consulta de tasa USD/COP por:", msg.sender);
        console.log("Tasa USD/COP actual:", _usdToCopRate);
        
        emit PriceRequested(msg.sender, "USD/COP");
        emit PriceProvided(msg.sender, "USD/COP", _usdToCopRate);
        
        return _usdToCopRate;
    }

    /**
     * @dev Obtiene la tasa de cambio VCOP a COP, actualizándola primero desde el pool
     * @return La tasa en formato de 6 decimales (ej: 1e6 para 1:1)
     */
    function getVcopToCopRate() external returns (uint256) {
        // Actualizar tasas desde el pool antes de devolver el valor
        updateRatesFromPool();
        
        console.log("Consulta de tasa VCOP/COP por:", msg.sender);
        console.log("Tasa VCOP/COP actual:", _vcopToCopRate);
        
        // Mostrar valor como decimal para verificación
        uint256 entero = _vcopToCopRate / 1e6;
        uint256 fraccion = _vcopToCopRate % 1e6;
        console.log("Valor VCOP/COP como decimal:", entero, ".", fraccion);
        
        emit PriceRequested(msg.sender, "VCOP/COP");
        emit PriceProvided(msg.sender, "VCOP/COP", _vcopToCopRate);
        
        return _vcopToCopRate;
    }
    
    /**
     * @dev Obtiene el precio de VCOP en USD directamente desde el pool
     * @return El precio en formato de 6 decimales
     */
    function getVcopToUsdPrice() external returns (uint256) {
        uint256 vcopToUsdPrice = getVcopToUsdPriceFromPool();
        
        console.log("Consulta de precio VCOP/USD por:", msg.sender);
        console.log("Precio VCOP/USD del pool:", vcopToUsdPrice);
        
        emit PriceRequested(msg.sender, "VCOP/USD");
        emit PriceProvided(msg.sender, "VCOP/USD", vcopToUsdPrice);
        
        return vcopToUsdPrice;
    }
    
    /**
     * @dev Obtiene el precio de VCOP para el mecanismo de rebase
     * Este método se mantiene compatible con el sistema de rebase existente
     * @return El precio en formato de 6 decimales
     */
    function getPrice() external returns (uint256) {
        // Actualizar tasas desde el pool antes de devolver el valor
        updateRatesFromPool();
        
        console.log("Consulta de precio para rebase por:", msg.sender);
        console.log("Tasa VCOP/COP actualizada:", _vcopToCopRate);
        
        // Mostrar valor como decimal para verificación
        uint256 entero = _vcopToCopRate / 1e6;
        uint256 fraccion = _vcopToCopRate % 1e6;
        console.log("Valor para rebase como decimal:", entero, ".", fraccion);
        
        emit PriceRequested(msg.sender, "REBASE");
        emit PriceProvided(msg.sender, "REBASE", _vcopToCopRate);
        
        return _vcopToCopRate;
    }

    /**
     * @dev Actualiza la tasa USD a COP manualmente (solo el propietario)
     * @param newRate La nueva tasa a establecer (en formato 6 decimales)
     */
    function setUsdToCopRate(uint256 newRate) external onlyOwner {
        require(newRate > 0, "Rate must be greater than zero");
        
        uint256 oldRate = _usdToCopRate;
        _usdToCopRate = newRate;
        
        console.log("Tasa USD/COP actualizada por:", msg.sender);
        console.log("Tasa anterior:", oldRate);
        console.log("Nueva tasa:", newRate);
        
        emit UsdToCopRateUpdated(oldRate, newRate);
    }
} 