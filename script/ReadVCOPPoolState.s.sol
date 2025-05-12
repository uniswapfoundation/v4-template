// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

/**
 * @title ReadVCOPPoolState
 * @notice Script para leer el estado del pool VCOP-USDC en Uniswap v4
 * Este script muestra como leer diferentes aspectos del estado del pool
 * usando las funciones proporcionadas por StateLibrary y calcular el precio
 * de VCOP en USD y COP
 */
contract ReadVCOPPoolState is Script {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;

    // Direcciones de los contratos principales
    IPoolManager public poolManager;
    
    // Direcciones de los tokens - actualizadas para SwapVCOP.s.sol
    address constant USDC_ADDRESS = 0xE7a4113a8a497DD72D29F35E188eEd7403e8B2E8;
    address constant VCOP_ADDRESS = 0xd16Ee99c7EA2B30c13c3dC298EADEE00B870BBCC;
    
    // Parametros del pool
    uint24 constant FEE = 3000; // 0.30%
    int24 constant TICK_SPACING = 60;
    address constant HOOK_ADDRESS = 0x866bf94370e8A7C9cDeAFb592C2ac62903e30040;
    
    // Tasa USD-COP (1 USD = 4200 COP)
    uint256 constant USD_TO_COP_RATE = 4200e6;

    function setUp() public {
        // Obtener direccion del PoolManager desde el entorno o usar el valor por defecto
        address poolManagerAddress;
        try vm.envAddress("POOL_MANAGER_ADDRESS") returns (address addr) {
            poolManagerAddress = addr;
        } catch {
            // Usar direccion por defecto de Base Sepolia de SwapVCOP.s.sol
            poolManagerAddress = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
        }
        poolManager = IPoolManager(poolManagerAddress);
    }

    function run() public {
        setUp();
        
        // Crear PoolKey para el pool VCOP-USDC
        PoolKey memory poolKey = _createPoolKey();
        PoolId poolId = poolKey.toId();
        
        // Determinar si VCOP es token0 o token1
        bool isVCOPToken0 = uint160(VCOP_ADDRESS) < uint160(USDC_ADDRESS);
        
        // Mostrar informacion del pool
        console.log("=== Estado del Pool VCOP-USDC ===");
        console.log("Pool Manager:", address(poolManager));
        console.log("VCOP es token0:", isVCOPToken0);
        console.log("Pool ID - currency0:", poolKey.currency0.toId());
        console.log("Pool ID - currency1:", poolKey.currency1.toId());
        console.log("Pool ID - fee:", poolKey.fee);
        
        // Obtener y mostrar el estado general del pool (Slot0)
        (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) = poolManager.getSlot0(poolId);
        console.log("Precio (sqrt):", sqrtPriceX96);
        console.log("Tick actual:", tick);
        console.log("Fee protocolo:", protocolFee);
        console.log("Fee LP:", lpFee);
        
        // Calcular y mostrar el precio de forma mas detallada
        uint256 rawPrice = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 1e18) >> 192;
        console.log("Precio raw (token1/token0):", rawPrice);
        
        // Calcular precio VCOP/USDC
        uint256 vcopToUsdPrice;
        if (isVCOPToken0) {
            // Si VCOP es token0, precio = 1/rawPrice
            vcopToUsdPrice = rawPrice > 0 ? (1e36 / rawPrice) : 0;
        } else {
            // Si VCOP es token1, precio = rawPrice
            vcopToUsdPrice = rawPrice;
        }
        
        // Ajustar a 6 decimales
        vcopToUsdPrice = vcopToUsdPrice / 1e12;
        console.log("Precio VCOP/USDC (6 decimales):", vcopToUsdPrice);
        
        // Calcular precio VCOP/COP
        // VCOP/COP = VCOP/USD * USD/COP
        uint256 vcopToCopPrice = (vcopToUsdPrice * USD_TO_COP_RATE) / 1e6;
        console.log("Tasa USD/COP:", USD_TO_COP_RATE / 1e6);
        console.log("Precio VCOP/COP (6 decimales):", vcopToCopPrice);
        
        // Calcular diferencia porcentual de VCOP/COP con respecto a 1:1 (ideal)
        int256 parityDifference;
        if (vcopToCopPrice > 1e6) {
            // VCOP vale mas que 1 COP
            parityDifference = int256(((vcopToCopPrice - 1e6) * 100) / 1e6);
            console.log("VCOP sobrevalorado en porcentaje:", uint256(parityDifference));
        } else if (vcopToCopPrice < 1e6) {
            // VCOP vale menos que 1 COP
            parityDifference = -int256(((1e6 - vcopToCopPrice) * 100) / 1e6);
            console.log("VCOP devaluado en porcentaje:", uint256(-parityDifference));
        } else {
            console.log("VCOP en paridad exacta con COP");
        }
        
        // Obtener y mostrar la liquidez total del pool
        uint128 liquidity = poolManager.getLiquidity(poolId);
        console.log("Liquidez total:", liquidity);
        
        // Informacion para rebase
        console.log("=== Informacion para Rebase ===");
        console.log("Umbral rebase superior (ejemplo): 105e4"); // 1.05 COP por VCOP
        console.log("Umbral rebase inferior (ejemplo): 95e4");  // 0.95 COP por VCOP
        if (vcopToCopPrice >= 105e4) {
            console.log("Se recomienda REBASE POSITIVO (expansion de suministro)");
        } else if (vcopToCopPrice <= 95e4) {
            console.log("Se recomienda REBASE NEGATIVO (contraccion de suministro)");
        } else {
            console.log("No se requiere rebase, precio dentro de umbrales");
        }
    }
    
    /**
     * @notice Crea una estructura PoolKey para el pool VCOP-USDC
     */
    function _createPoolKey() internal pure returns (PoolKey memory) {
        // Determinar el orden correcto de los tokens (lexicografico)
        Currency currency0;
        Currency currency1;
        
        if (uint160(VCOP_ADDRESS) < uint160(USDC_ADDRESS)) {
            currency0 = Currency.wrap(VCOP_ADDRESS);
            currency1 = Currency.wrap(USDC_ADDRESS);
        } else {
            currency0 = Currency.wrap(USDC_ADDRESS);
            currency1 = Currency.wrap(VCOP_ADDRESS);
        }
        
        // Crear la estructura PoolKey
        return PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(HOOK_ADDRESS)
        });
    }
    
    /**
     * @notice Obtiene informacion sobre una posicion especifica de liquidez
     * @param owner Direccion del propietario de la posicion
     * @param tickLower Tick inferior del rango
     * @param tickUpper Tick superior del rango
     * @param salt Valor de salt para identificar la posicion
     */
    function getPositionInfo(
        address owner,
        int24 tickLower,
        int24 tickUpper,
        bytes32 salt
    ) public view returns (
        uint128 liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128
    ) {
        PoolKey memory poolKey = _createPoolKey();
        return poolManager.getPositionInfo(poolKey.toId(), owner, tickLower, tickUpper, salt);
    }
} 