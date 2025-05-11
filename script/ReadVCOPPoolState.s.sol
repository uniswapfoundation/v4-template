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
 * Este script muestra cómo leer diferentes aspectos del estado del pool
 * usando las funciones proporcionadas por StateLibrary
 */
contract ReadVCOPPoolState is Script {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;

    // Direcciones de los contratos principales
    IPoolManager public poolManager;
    
    // Direcciones de los tokens
    address constant USDC_ADDRESS = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address constant VCOP_ADDRESS = 0x9654e816C592b9794a6c20F97019C952BD69E1B0;
    
    // Parámetros del pool
    uint24 constant FEE = 3000; // 0.30%
    int24 constant TICK_SPACING = 60;
    address constant HOOK_ADDRESS = 0x4eB4B9f731ECCaB556f3516550dd4A68fc3b0040;

    function setUp() public {
        // Obtener dirección del PoolManager desde el entorno
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        poolManager = IPoolManager(poolManagerAddress);
    }

    function run() public {
        setUp();
        
        // Crear PoolKey para el pool VCOP-USDC
        PoolKey memory poolKey = _createPoolKey();
        PoolId poolId = poolKey.toId();
        
        // Mostrar información del pool
        console.log("=== Estado del Pool VCOP-USDC ===");
        console.log("Pool ID - currency0:", poolKey.currency0.toId());
        console.log("Pool ID - currency1:", poolKey.currency1.toId());
        console.log("Pool ID - fee:", poolKey.fee);
        
        // Obtener y mostrar el estado general del pool (Slot0)
        (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) = poolManager.getSlot0(poolId);
        console.log("Precio (sqrt):", sqrtPriceX96);
        console.log("Tick actual:", tick);
        console.log("Fee protocolo:", protocolFee);
        console.log("Fee LP:", lpFee);
        
        // Calcular y mostrar el precio actual
        uint256 price = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 1e18) >> 192;
        console.log("Precio actual:", price);
        
        // Obtener y mostrar la liquidez total del pool
        uint128 liquidity = poolManager.getLiquidity(poolId);
        console.log("Liquidez total:", liquidity);
        
        // Comentado hasta verificar si la función está disponible en la versión actual
        // (uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) = poolManager.getFeeGrowthGlobal(poolId);
        // console.log("Fee Growth Global Token0:", feeGrowthGlobal0X128);
        // console.log("Fee Growth Global Token1:", feeGrowthGlobal1X128);
    }
    
    /**
     * @notice Crea una estructura PoolKey para el pool VCOP-USDC
     */
    function _createPoolKey() internal pure returns (PoolKey memory) {
        // Crear Currency para VCOP y USDC
        Currency currency0 = Currency.wrap(USDC_ADDRESS);
        Currency currency1 = Currency.wrap(VCOP_ADDRESS);
        
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
     * @notice Obtiene información sobre una posición específica de liquidez
     * @param owner Dirección del propietario de la posición
     * @param tickLower Tick inferior del rango
     * @param tickUpper Tick superior del rango
     * @param salt Valor de salt para identificar la posición
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