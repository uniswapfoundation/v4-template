// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {VCOPOracle} from "src/VCOPOracle.sol";

/**
 * @title TestVCOPOracle
 * @notice Script para probar el oraculo VCOP con Uniswap v4
 */
contract TestVCOPOracle is Script {
    // Direccion del oraculo - debe actualizarse con la direccion real despues del despliegue
    address public oracleAddress;

    function setUp() public {
        // Obtener direccion del oraculo desde el entorno o usar direccion por defecto
        try vm.envAddress("VCOP_ORACLE_ADDRESS") returns (address addr) {
            oracleAddress = addr;
        } catch {
            // Si no se proporciona, usar una direccion por defecto (reemplazar con la real)
            revert("No se ha configurado la direccion del oraculo. Usar --env VCOP_ORACLE_ADDRESS=0x...");
        }
    }

    function run() public {
        setUp();
        
        console.log("Probando VCOPOracle en direccion:", oracleAddress);
        VCOPOracle oracle = VCOPOracle(oracleAddress);
        
        // Imprimir configuracion del oraculo
        console.log("Pool Manager:", address(oracle.poolManager()));
        console.log("VCOP Address:", oracle.vcopAddress());
        console.log("USDC Address:", oracle.usdcAddress());
        console.log("VCOP es token0:", oracle.isVCOPToken0());
        
        // Ejecutar prueba de obtencion de precio desde el pool
        vm.startBroadcast();
        
        // Obtener precio de VCOP en USD directamente del pool
        uint256 vcopToUsdPrice = oracle.getVcopToUsdPriceFromPool();
        console.log("Precio VCOP/USD del pool (vista):", vcopToUsdPrice);
        
        // Actualizar y obtener tasas desde el pool
        (uint256 vcopToCopRate, uint256 updatedVcopToUsdPrice) = oracle.updateRatesFromPool();
        console.log("Tasa VCOP/COP actualizada:", vcopToCopRate);
        console.log("Precio VCOP/USD actualizado:", updatedVcopToUsdPrice);
        
        // Probar funciones de obtencion de precios
        uint256 usdToCopRate = oracle.getUsdToCopRate();
        console.log("Tasa USD/COP:", usdToCopRate);
        
        uint256 manualVcopToCopRate = oracle.getVcopToCopRate();
        console.log("Tasa VCOP/COP (con actualizacion):", manualVcopToCopRate);
        
        uint256 orVcopToUsdPrice = oracle.getVcopToUsdPrice();
        console.log("Precio VCOP/USD (directo):", orVcopToUsdPrice);
        
        // Obtener precio para rebase
        uint256 rebasePrice = oracle.getPrice();
        console.log("Precio para rebase:", rebasePrice);
        
        // Verificar si se necesita rebase
        if (rebasePrice >= 105e4) {
            console.log("Se recomienda REBASE POSITIVO (expansion)");
        } else if (rebasePrice <= 95e4) {
            console.log("Se recomienda REBASE NEGATIVO (contraccion)");
        } else {
            console.log("No se requiere rebase, precio dentro de umbrales");
        }
        
        vm.stopBroadcast();
    }
} 