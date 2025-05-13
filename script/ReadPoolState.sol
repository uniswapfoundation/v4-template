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
 * @title ReadPoolState
 * @notice Script para leer el estado de una pool en Uniswap v4
 */
contract ReadPoolState is Script {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;

    function run() public view {
        // Direcciones de contratos y tokens
        address POOL_MANAGER_ADDRESS = vm.envAddress("POOL_MANAGER_ADDRESS");
        address CURRENCY0_ADDRESS = vm.envAddress("CURRENCY0_ADDRESS");
        address CURRENCY1_ADDRESS = vm.envAddress("CURRENCY1_ADDRESS");
        uint24 FEE = uint24(vm.envUint("FEE"));
        int24 TICK_SPACING = int24(int256(vm.envUint("TICK_SPACING")));
        address HOOK_ADDRESS = vm.envAddress("HOOK_ADDRESS");
        
        IPoolManager poolManager = IPoolManager(POOL_MANAGER_ADDRESS);
        
        // Crear PoolKey para el pool
        PoolKey memory poolKey = _createPoolKey(
            CURRENCY0_ADDRESS,
            CURRENCY1_ADDRESS,
            FEE,
            TICK_SPACING,
            HOOK_ADDRESS
        );
        
        PoolId poolId = poolKey.toId();
        
        // Mostrar información del pool
        console.log("=== Estado del Pool ===");
        console.log("Currency0:", vm.toString(CURRENCY0_ADDRESS));
        console.log("Currency1:", vm.toString(CURRENCY1_ADDRESS));
        console.log("Fee:", FEE);
        
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
    }
    
    /**
     * @notice Crea una estructura PoolKey para el pool
     */
    function _createPoolKey(
        address currency0Address,
        address currency1Address,
        uint24 fee,
        int24 tickSpacing,
        address hookAddress
    ) internal pure returns (PoolKey memory) {
        // Crear Currency para los tokens
        Currency currency0 = Currency.wrap(currency0Address);
        Currency currency1 = Currency.wrap(currency1Address);
        
        // Crear la estructura PoolKey
        return PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hookAddress)
        });
    }
} 