// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {VCOPPriceCalculator} from "../src/VCOPPriceCalculator.sol";
import {VCOPOracle} from "../src/VCOPOracle.sol";

/**
 * @title TestVCOPPriceCalculator
 * @notice Script para probar el calculador de precios de VCOP con un pool existente
 */
contract TestVCOPPriceCalculator is Script {
    // Configuracion - Base Sepolia
    address constant POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
    address constant VCOP_ADDRESS = 0x426cE1ddcf18BA757f919632a32dC9Bfe8307f2d;
    address constant USDC_ADDRESS = 0x451CfC39fd0ED23F36D76AE6D53dF35D1457e756;
    address constant ORACLE_ADDRESS = 0x5B06a939362B1136cd95c0db290F40D30F5F1EEe;
    address constant HOOK_ADDRESS = 0x776C291474ea3847323ABBb41C32d11054940040;
    address constant PRICE_CALCULATOR_ADDRESS = 0xf4b834dac090732648C70bcA937b151077292827;
    uint24 constant FEE = 3000; // 0.30%
    int24 constant TICK_SPACING = 60;
    
    // Tasa USD-COP (1 USD = 4200 COP)
    uint256 constant USD_TO_COP_RATE = 4200e6;
    
    function run() public view {
        console.log("Probando VCOPPriceCalculator en Base Sepolia");
        console.log("Usando contratos desplegados:");
        console.log("- VCOP Token:", VCOP_ADDRESS);
        console.log("- USDC Token:", USDC_ADDRESS);
        console.log("- Oracle:", ORACLE_ADDRESS);
        console.log("- Hook:", HOOK_ADDRESS);
        console.log("- Price Calculator:", PRICE_CALCULATOR_ADDRESS);
        
        // Si queremos probar con un calculador ya desplegado
        VCOPPriceCalculator calculator = VCOPPriceCalculator(PRICE_CALCULATOR_ADDRESS);
        
        // Comprobar si VCOP es token0
        bool isVCOPToken0 = calculator.isVCOPToken0();
        console.log("VCOP es token0:", isVCOPToken0);
        
        // Obtener precios usando el calculador
        (uint256 vcopToUsdPrice, int24 tick) = calculator.getVcopToUsdPriceFromPool();
        console.log("Precio VCOP/USDC (6 decimales):", vcopToUsdPrice);
        console.log("Precio VCOP/USDC:", vcopToUsdPrice / 1e6);
        console.log("Tick actual:", tick);
        
        // Obtener precio VCOP/COP
        (uint256 vcopToCopPrice, ) = calculator.getVcopToCopPrice();
        console.log("Precio VCOP/COP (6 decimales):", vcopToCopPrice);
        console.log("Precio VCOP/COP:", vcopToCopPrice / 1e6);
        
        // Verificar si está en paridad 1:1
        bool isAtParity = calculator.isVcopAtParity();
        console.log("VCOP esta en paridad 1:1 con COP?", isAtParity);
        
        // Prueba del método que devuelve todos los valores
        (uint256 usdPrice, uint256 copPrice, int24 currentTick, bool parity) = calculator.calculateAllPrices();
        console.log("=== Resumen de precios ===");
        console.log("Precio VCOP/USDC:", usdPrice / 1e6);
        console.log("Precio VCOP/COP:", copPrice / 1e6);
        console.log("Tick actual:", currentTick);
        console.log("En paridad 1:1:", parity);
        
        // Verificar con el Oráculo existente
        VCOPOracle oracle = VCOPOracle(ORACLE_ADDRESS);
        console.log("=== Verificacion via Oracle ===");
        bool oracleUsingCalculator = address(oracle.priceCalculator()) == PRICE_CALCULATOR_ADDRESS;
        console.log("Oracle configurado con calculador?", oracleUsingCalculator);

        if (!oracleUsingCalculator) {
            console.log("ADVERTENCIA: El oraculo no esta usando el calculador de precios.");
            console.log("Para configurarlo, ejecuta oracle.setPriceCalculator(PRICE_CALCULATOR_ADDRESS)");
        }
    }
} 