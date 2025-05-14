// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {VCOPCollateralized} from "../src/VcopCollateral/VCOPCollateralized.sol";
import {VCOPOracle} from "../src/VcopCollateral/VCOPOracle.sol";
import {VCOPPriceCalculator} from "../src/VcopCollateral/VCOPPriceCalculator.sol";
import {VCOPCollateralManager} from "../src/VcopCollateral/VCOPCollateralManager.sol";
import {DeployMockUSDC} from "./DeployMockUSDC.s.sol";

/**
 * @title DeployVCOPBase
 * @notice Script para desplegar los contratos base del sistema VCOP
 * @dev Para ejecutar: forge script script/DeployVCOPBase.sol:DeployVCOPBase --via-ir --broadcast --fork-url https://sepolia.base.org
 */
contract DeployVCOPBase is Script {
    // API Key dummy para evitar errores de verificacion
    string constant DUMMY_API_KEY = "ABCDEFGHIJKLMNOPQRSTUVWXYZ123456";
    
    // Tasa inicial USD/COP (4200 COP = 1 USD)
    uint256 initialUsdToCopRate = 4200e6; // Con 6 decimales

    function run() public returns (
        address usdcAddress,
        address vcopAddress,
        address oracleAddress,
        address collateralManagerAddress
    ) {
        // Establecer una clave de API dummy para Etherscan
        vm.setEnv("ETHERSCAN_API_KEY", DUMMY_API_KEY);
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        
        console.logString("Verificando red y saldos...");
        console.logString("Direccion del desplegador:"); 
        console.logAddress(deployerAddress);
        
        // === PASO 1: Desplegar USDC simulado ===
        console.logString("=== PASO 1: Desplegando USDC Simulado ===");
        
        // Desplegar el USDC simulado
        DeployMockUSDC usdcDeployer = new DeployMockUSDC();
        usdcAddress = usdcDeployer.run();
        
        console.logString("Direccion de USDC simulado:"); 
        console.logAddress(usdcAddress);
        
        // Guardar para el siguiente script
        vm.setEnv("USDC_ADDRESS", vm.toString(usdcAddress));
        
        // === PASO 2: Desplegar VCOP Colateralizado ===
        console.logString("=== PASO 2: Desplegando VCOP Colateralizado ===");
        vm.startBroadcast(deployerPrivateKey);
        
        // Despliegue de VCOP Colateralizado
        VCOPCollateralized vcop = new VCOPCollateralized();
        vcopAddress = address(vcop);
        
        console.logString("VCOP Colateralizado desplegado en:"); 
        console.logAddress(vcopAddress);
        
        vm.stopBroadcast();
        
        // Guardar para el siguiente script
        vm.setEnv("VCOP_ADDRESS", vm.toString(vcopAddress));
        
        // === PASO 3: Desplegar Oracle y Calculador de Precios ===
        console.logString("=== PASO 3: Desplegando Oracle y Calculador de Precios ===");
        vm.startBroadcast(deployerPrivateKey);
        
        // Despliegue del oráculo con tasa inicial
        VCOPOracle oracle = new VCOPOracle(
            initialUsdToCopRate,
            poolManagerAddress,
            vcopAddress,
            usdcAddress,
            3000, // lpFee 0.3%
            60,   // tickSpacing
            address(0) // Hook se configurará después
        );
        oracleAddress = address(oracle);
        
        console.logString("Oracle desplegado en:"); 
        console.logAddress(oracleAddress);
        
        vm.stopBroadcast();
        
        // Guardar para el siguiente script
        vm.setEnv("ORACLE_ADDRESS", vm.toString(oracleAddress));
        
        // === PASO 4: Desplegar VCOPCollateralManager ===
        console.logString("=== PASO 4: Desplegando Collateral Manager ===");
        vm.startBroadcast(deployerPrivateKey);
        
        // Desplegar el gestor de colateral
        VCOPCollateralManager collateralManager = new VCOPCollateralManager(
            vcopAddress,
            oracleAddress
        );
        collateralManagerAddress = address(collateralManager);
        
        console.logString("Collateral Manager desplegado en:");
        console.logAddress(collateralManagerAddress);
        
        vm.stopBroadcast();
        
        // Guardar para el siguiente script
        vm.setEnv("COLLATERAL_MANAGER_ADDRESS", vm.toString(collateralManagerAddress));
        
        console.logString("=== Despliegue base completado exitosamente ===");
        console.logString("Para continuar, ejecute ConfigureVCOPSystem.sol");
        
        return (usdcAddress, vcopAddress, oracleAddress, collateralManagerAddress);
    }
} 