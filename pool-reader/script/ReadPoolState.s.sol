// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";

/**
 * @title ReadPoolState
 * @notice Script para leer el estado de una pool en Uniswap v4 usando StateLibrary
 * Este script implementa las funciones descritas en la documentacion oficial
 * para leer el estado de un pool de Uniswap v4
 */
contract ReadPoolState is Script {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;

    // Estructura para almacenar los parametros del pool
    struct PoolParams {
        address poolManagerAddress;
        address currency0Address;
        address currency1Address;
        uint24 fee;
        int24 tickSpacing;
        address hookAddress;
    }

    function run() public view {
        // Leer parametros del entorno
        PoolParams memory params = getPoolParams();
        
        // Conectar al PoolManager
        IPoolManager poolManager = IPoolManager(params.poolManagerAddress);
        
        // Crear PoolKey para el pool
        PoolKey memory poolKey = _createPoolKey(params);        
        PoolId poolId = poolKey.toId();
        
        // Mostrar informacion del pool
        console.log("=== Estado del Pool ===");
        console.log("Currency0:", params.currency0Address);
        console.log("Currency1:", params.currency1Address);
        console.log("Fee:", params.fee);
        
        // Obtener y mostrar el estado general del pool (Slot0)
        (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) = poolManager.getSlot0(poolId);
        console.log("\n=== Slot0 ===");
        console.log("Precio (sqrt):", sqrtPriceX96);
        console.log("Tick actual:", tick);
        console.log("Fee protocolo:", protocolFee);
        console.log("Fee LP:", lpFee);
        
        // Calcular y mostrar el precio actual
        uint256 price = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 1e18) >> 192;
        console.log("Precio actual:", price);
        
        // Obtener y mostrar la liquidez total del pool
        uint128 liquidity = poolManager.getLiquidity(poolId);
        console.log("\n=== Liquidez ===");
        console.log("Liquidez total:", liquidity);
        
        // Calcular y mostrar la cantidad de cada token
        if (liquidity > 0) {
            // Para calcular las cantidades, necesitamos el rango de ticks
            // Si no se especifica, usaremos un rango amplio alrededor del tick actual
            int24 tickLower;
            int24 tickUpper;
            
            if (vm.envOr("TICK_LOWER_SET", false)) {
                tickLower = int24(int256(vm.envUint("TICK_LOWER")));
            } else {
                tickLower = tick - int24(10 * params.tickSpacing);
            }
            
            if (vm.envOr("TICK_UPPER_SET", false)) {
                tickUpper = int24(int256(vm.envUint("TICK_UPPER")));
            } else {
                tickUpper = tick + int24(10 * params.tickSpacing);
            }
            
            console.log("Usando rango de ticks");
            console.log("Tick Lower:", tickLower);
            console.log("Tick Upper:", tickUpper);
            
            // Calcular las cantidades aproximadas usando un método más simple
            uint256 amount0 = approximateAmount0(liquidity, sqrtPriceX96);
            uint256 amount1 = approximateAmount1(liquidity, sqrtPriceX96);
            
            console.log("\n=== Cantidades Aproximadas de Tokens ===");
            console.log("Token0 (%s):", params.currency0Address);
            console.log("  Cantidad:", amount0);
            console.log("Token1 (%s):", params.currency1Address);
            console.log("  Cantidad:", amount1);
        }
        
        // Si se proporcionaron detalles de una posicion especifica, mostrarlos
        if (vm.envOr("SHOW_POSITION", false)) {
            address owner = vm.envAddress("POSITION_OWNER");
            int24 tickLower = int24(int256(vm.envUint("POSITION_TICK_LOWER")));
            int24 tickUpper = int24(int256(vm.envUint("POSITION_TICK_UPPER")));
            bytes32 positionSalt = vm.envBytes32("POSITION_SALT");
            
            console.log("\n=== Informacion de Posicion ===");
            console.log("Owner:", owner);
            console.log("Tick Lower:", tickLower);
            console.log("Tick Upper:", tickUpper);
            
            (uint128 posLiquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128) = 
                poolManager.getPositionInfo(poolId, owner, tickLower, tickUpper, positionSalt);
                
            console.log("Liquidez posicion:", posLiquidity);
            console.log("Fee Growth Inside Token0:", feeGrowthInside0LastX128);
            console.log("Fee Growth Inside Token1:", feeGrowthInside1LastX128);
            
            // Calcular las cantidades de tokens para esta posición
            if (posLiquidity > 0) {
                uint256 amount0 = approximateAmount0(posLiquidity, sqrtPriceX96);
                uint256 amount1 = approximateAmount1(posLiquidity, sqrtPriceX96);
                
                console.log("Cantidad Aproximada Token0:", amount0);
                console.log("Cantidad Aproximada Token1:", amount1);
            }
        }
    }
    
    /**
     * @notice Calcula aproximadamente la cantidad de token0 en base a la liquidez y precio actual
     * @param liquidity Liquidez
     * @param sqrtPriceX96 Precio sqrt actual
     * @return amount0 Cantidad aproximada del token0
     */
    function approximateAmount0(uint128 liquidity, uint160 sqrtPriceX96) public pure returns (uint256) {
        uint256 Q96 = 2**96;
        // Cálculo aproximado: amount0 = L * Q96 / sqrtP
        return FullMath.mulDiv(uint256(liquidity), Q96, uint256(sqrtPriceX96));
    }
    
    /**
     * @notice Calcula aproximadamente la cantidad de token1 en base a la liquidez y precio actual
     * @param liquidity Liquidez
     * @param sqrtPriceX96 Precio sqrt actual
     * @return amount1 Cantidad aproximada del token1
     */
    function approximateAmount1(uint128 liquidity, uint160 sqrtPriceX96) public pure returns (uint256) {
        uint256 Q96 = 2**96;
        // Cálculo aproximado: amount1 = L * sqrtP / Q96
        return FullMath.mulDiv(uint256(liquidity), uint256(sqrtPriceX96), Q96);
    }
    
    /**
     * @notice Lee los parametros del pool desde variables de entorno
     */
    function getPoolParams() internal view returns (PoolParams memory) {
        return PoolParams({
            poolManagerAddress: vm.envAddress("POOL_MANAGER_ADDRESS"),
            currency0Address: vm.envAddress("CURRENCY0_ADDRESS"),
            currency1Address: vm.envAddress("CURRENCY1_ADDRESS"),
            fee: uint24(vm.envUint("FEE")),
            tickSpacing: int24(int256(vm.envUint("TICK_SPACING"))),
            hookAddress: vm.envAddress("HOOK_ADDRESS")
        });
    }
    
    /**
     * @notice Crea una estructura PoolKey para el pool
     */
    function _createPoolKey(PoolParams memory params) internal pure returns (PoolKey memory) {
        // Crear Currency para los tokens
        Currency currency0 = Currency.wrap(params.currency0Address);
        Currency currency1 = Currency.wrap(params.currency1Address);
        
        // Crear la estructura PoolKey
        return PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: params.fee,
            tickSpacing: params.tickSpacing,
            hooks: IHooks(params.hookAddress)
        });
    }
} 