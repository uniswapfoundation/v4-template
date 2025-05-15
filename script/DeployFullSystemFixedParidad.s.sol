// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {DeployVCOPBase} from "./DeployVCOPBase.sol";
import {ConfigureVCOPSystem} from "./ConfigureVCOPSystem.sol";
import {VCOPOracle} from "../src/VcopCollateral/VCOPOracle.sol";
import {VCOPPriceCalculator} from "../src/VcopCollateral/VCOPPriceCalculator.sol";

/**
 * @title DeployFullSystemFixedParidad
 * @notice Script to deploy the entire VCOP system with corrected paridad (1:1 VCOP/COP)
 * @dev Run with: forge script script/DeployFullSystemFixedParidad.s.sol:DeployFullSystemFixedParidad --broadcast --rpc-url https://sepolia.base.org
 */
contract DeployFullSystemFixedParidad is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        // Configurar un gas price más alto para acelerar las transacciones (3 gwei)
        vm.txGasPrice(3_000_000_000); // 3 gwei
        
        console.log("=== Desplegando sistema completo VCOP con paridad fija 1:1 ===");
        console.log("Deployer address:", deployerAddress);
        console.log("Gas price configurado: 3 gwei");
        
        // Paso 1: Desplegar los contratos base con DeployVCOPBase
        DeployVCOPBase baseDeployer = new DeployVCOPBase();
        console.log("Ejecutando DeployVCOPBase...");
        
        (
            address usdcAddress, 
            address vcopAddress, 
            address oracleAddress, 
            address collateralManagerAddress
        ) = baseDeployer.run();
        
        console.log("Contratos base desplegados:");
        console.log("USDC:", usdcAddress);
        console.log("VCOP:", vcopAddress);
        console.log("Oracle:", oracleAddress);
        console.log("CollateralManager:", collateralManagerAddress);
        
        // Verificar que el oráculo tenga la configuración correcta
        vm.startBroadcast(deployerPrivateKey);
        
        VCOPOracle oracle = VCOPOracle(oracleAddress);
        uint256 vcopToCopRate = oracle.getVcopToCopRateView();
        uint256 usdToCopRate = oracle.getUsdToCopRateView();
        
        console.log("Verificando configuracion inicial del oraculo:");
        console.log("VCOP/COP rate:", vcopToCopRate);
        console.log("USD/COP rate:", usdToCopRate);
        
        // Forzar actualización para asegurar tasa VCOP/COP = 1:1
        (uint256 newVcopToCopRate, uint256 vcopToUsdPrice) = oracle.updateRatesFromPool();
        console.log("Oraculo actualizado:");
        console.log("VCOP/COP rate despues de actualizacion:", newVcopToCopRate);
        console.log("VCOP/USD price:", vcopToUsdPrice);
        
        // Verificar que sea efectivamente 1:1
        require(newVcopToCopRate == 1000000, "La tasa VCOP/COP no es 1:1 (1,000,000)");
        console.log("Confirmado: La tasa VCOP/COP esta correctamente fijada en 1:1");
        
        vm.stopBroadcast();
        
        // Paso 2: Configurar el sistema con ConfigureVCOPSystem
        ConfigureVCOPSystem configSystem = new ConfigureVCOPSystem();
        console.log("Ejecutando ConfigureVCOPSystem...");
        
        configSystem.run();
        
        console.log("Sistema VCOP completamente desplegado y configurado con paridad fija 1:1");
        console.log("IMPORTANTE: Verificar que las transacciones de swap esten usando la tasa correcta");
        console.log("Prueba con: make swap-usdc-to-vcop AMOUNT=10000000");
        
        // Verificación final de tasas
        vm.startBroadcast(deployerPrivateKey);
        
        vcopToCopRate = oracle.getVcopToCopRateView();
        usdToCopRate = oracle.getUsdToCopRateView();
        
        console.log("=== Verificacion final de tasas ===");
        console.log("VCOP/COP rate:", vcopToCopRate);
        console.log("USD/COP rate:", usdToCopRate);
        console.log("Tasa de conversion esperada: 1 USDC = 4,200 VCOP");
        
        // Calcular tasa efectiva
        uint256 effectiveRate = (usdToCopRate * 1e6) / vcopToCopRate;
        console.log("Tasa efectiva USDC/VCOP:", effectiveRate);
        
        vm.stopBroadcast();
    }
} 