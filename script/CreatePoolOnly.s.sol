// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

/**
 * @title CreatePoolOnly
 * @notice Script simplified to just create the pool without adding liquidity
 */
contract CreatePoolOnly is Script {
    // Parametros configurables para el pool
    uint24 lpFee = 3000; // 0.30%
    int24 tickSpacing = 60;
    uint160 startingPrice = 79228162514264337593543950336; // sqrt(1) * 2^96

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        address positionManagerAddress = vm.envAddress("POSITION_MANAGER_ADDRESS");
        address vcopAddress = vm.envAddress("VCOP_ADDRESS");
        address hookAddress = vm.envAddress("HOOK_ADDRESS");
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        
        console.log("=== Usando contratos ya desplegados ===");
        console.log("VCOP:", vcopAddress);
        console.log("Hook:", hookAddress);
        console.log("USDC:", usdcAddress);
        
        // Referencias a contratos externos de Uniswap
        PositionManager positionManager = PositionManager(payable(positionManagerAddress));
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Crear Currency para VCOP y USDC
        Currency vcopCurrency = Currency.wrap(vcopAddress);
        Currency usdcCurrency = Currency.wrap(usdcAddress);
        
        // Asegurar que las monedas esten en orden correcto (menor direccion primero)
        Currency currency0;
        Currency currency1;
        
        if (vcopAddress < usdcAddress) {
            currency0 = vcopCurrency;
            currency1 = usdcCurrency;
            console.log("VCOP es token0");
        } else {
            currency0 = usdcCurrency;
            currency1 = vcopCurrency;
            console.log("USDC es token0");
        }
        
        // Crear la estructura PoolKey
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hookAddress)
        });
        
        // Inicializar pool con PositionManager
        positionManager.initializePool(poolKey, startingPrice);
        
        console.log("Pool creado con exito");
        
        vm.stopBroadcast();
    }
} 