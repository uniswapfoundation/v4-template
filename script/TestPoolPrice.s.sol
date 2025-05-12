// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {FixedPoint96} from "v4-core/src/libraries/FixedPoint96.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

/**
 * @title TestPoolPrice
 * @notice Script para leer el precio directamente de la pool VCOP-USDC usando sqrtPriceX96
 */
contract TestPoolPrice is Script {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;

    // Configuracion - Base Sepolia
    address constant POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
    address constant VCOP_ADDRESS = 0x70370F8507f0c40D5Ed3222F669B0727FFF8C12c;
    address constant USDC_ADDRESS = 0xAE919425E485C6101E391091350E3f0304749574;
    uint24 constant FEE = 3000; // 0.30%
    int24 constant TICK_SPACING = 60;
    address constant HOOK_ADDRESS = 0x1E70FbbF7A9ADcD550BaeE80E58B244EcdFF0040;
    
    // Tasa USD-COP (1 USD = 4200 COP)
    uint256 constant USD_TO_COP_RATE = 4200e6;

    function run() public view {
        console.log("Leyendo precio de la pool VCOP-USDC en Base Sepolia");
        
        // Crear instancia del PoolManager
        IPoolManager poolManager = IPoolManager(POOL_MANAGER);
        
        // Determinar si VCOP es token0 o token1 (ordenamiento lexicografico)
        bool isVCOPToken0 = uint160(VCOP_ADDRESS) < uint160(USDC_ADDRESS);
        console.log("VCOP es token0:", isVCOPToken0);
        
        // Crear PoolKey basado en el orden correcto
        PoolKey memory poolKey = _createPoolKey(isVCOPToken0);
        PoolId poolId = poolKey.toId();
        
        // Obtener sqrtPriceX96 y tick del pool
        (uint160 sqrtPriceX96, int24 tick,, ) = poolManager.getSlot0(poolId);
        console.log("sqrtPriceX96:", sqrtPriceX96);
        console.log("Tick actual:", tick);
        
        // Cálculo desde sqrtPriceX96
        console.log("=== Calculo de Precio VCOP/USDC ===");
        uint256 rawPrice = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) / (1 << 192);
        console.log("Precio raw sin escalar (token1/token0):", rawPrice);
        
        // Escalar el precio raw a 18 decimales
        rawPrice = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 1e18) >> 192;
        console.log("Precio raw con 18 decimales (token1/token0):", rawPrice);
        
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
        console.log("Precio VCOP/USDC:", vcopToUsdPrice / 1e6);
        
        // Calcular precio VCOP/COP usando el precio de sqrtPriceX96
        uint256 vcopToCopPrice = (vcopToUsdPrice * USD_TO_COP_RATE) / 1e6;
        
        console.log("=== Conversion a COP ===");
        console.log("Tasa USD/COP:", USD_TO_COP_RATE / 1e6);
        console.log("Precio VCOP/COP (6 decimales):", vcopToCopPrice);
        console.log("Precio VCOP/COP:", vcopToCopPrice / 1e6);
    }
    
    /**
     * @dev Crea una estructura PoolKey para el pool VCOP-USDC
     */
    function _createPoolKey(bool isVCOPToken0) internal pure returns (PoolKey memory) {
        Currency currency0;
        Currency currency1;
        
        // Asignar tokens según el orden correcto
        if (isVCOPToken0) {
            currency0 = Currency.wrap(VCOP_ADDRESS);
            currency1 = Currency.wrap(USDC_ADDRESS);
        } else {
            currency0 = Currency.wrap(USDC_ADDRESS);
            currency1 = Currency.wrap(VCOP_ADDRESS);
        }
        
        return PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(HOOK_ADDRESS)
        });
    }
} 