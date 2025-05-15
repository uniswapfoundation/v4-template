// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {VCOPOracle} from "../src/VcopCollateral/VCOPOracle.sol";
import {VCOPCollateralManager} from "../src/VcopCollateral/VCOPCollateralManager.sol";
import {VCOPPriceCalculator} from "../src/VcopCollateral/VCOPPriceCalculator.sol";

/**
 * @title UpdateOracle
 * @notice Script to deploy a new oracle with fixed paridad rate
 * @dev Run with: forge script script/UpdateOracle.s.sol:UpdateOracle --broadcast --rpc-url https://sepolia.base.org
 */
contract UpdateOracle is Script {
    // Contract addresses (usar las direcciones más recientes)
    address constant POOL_MANAGER_ADDRESS = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
    address constant VCOP_ADDRESS = 0xbbF67a9C2a6E33B405ff30C948275c2154B36E3A;
    address constant USDC_ADDRESS = 0x1D954BcfB060a3dc5A49536243545334dD536493;
    address constant HOOK_ADDRESS = 0xe0457171D72461135346bcEAc4BF1F381c61C4C0;
    address constant MANAGER_ADDRESS = 0x2D644FC74e5fe6598b0843f149b02bFEf99Ef383;
    
    // Dirección del oráculo actual para reemplazar
    address constant OLD_ORACLE_ADDRESS = 0x352a80294311db57562f625cFcab502ccAd61581;
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        console.log("=== Actualizando Oraculo VCOP ===");
        console.log("Deployer address:", deployerAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Desplegar un nuevo oráculo con la implementación corregida
        uint256 initialUsdToCopRate = 4200e6; // Con 6 decimales
        
        VCOPOracle newOracle = new VCOPOracle(
            initialUsdToCopRate, // Tasa USD/COP inicial
            POOL_MANAGER_ADDRESS,
            VCOP_ADDRESS,
            USDC_ADDRESS,
            3000, // lpFee 0.3%
            60,   // tickSpacing
            HOOK_ADDRESS // Hook address
        );
        
        address newOracleAddress = address(newOracle);
        console.log("Nuevo oraculo desplegado en:", newOracleAddress);
        
        // 2. Desplegar un nuevo calculador de precios
        VCOPPriceCalculator newCalculator = new VCOPPriceCalculator(
            POOL_MANAGER_ADDRESS,
            VCOP_ADDRESS,
            USDC_ADDRESS,
            3000, // lpFee
            60,   // tickSpacing
            HOOK_ADDRESS,
            4200e6 // Tasa USD/COP inicial
        );
        
        address newCalculatorAddress = address(newCalculator);
        console.log("Nuevo calculador desplegado en:", newCalculatorAddress);
        
        // 3. Configurar el calculador en el oráculo
        newOracle.setPriceCalculator(newCalculatorAddress);
        console.log("Calculador configurado en el oraculo");
        
        // 4. Actualizar la referencia al oráculo en el Manager
        VCOPCollateralManager manager = VCOPCollateralManager(MANAGER_ADDRESS);
        
        // Intentar actualizar el oráculo si existe un método para hacerlo
        // (esto depende de si la implementación lo permite)
        // Si no existe este método, necesitarás desplegar un nuevo manager también
        try this.updateOracleReferenceInManager(manager, newOracleAddress) {
            console.log("Referencia del oraculo actualizada en el manager");
        } catch {
            console.log("ADVERTENCIA: No se pudo actualizar la referencia del oraculo en el manager");
            console.log("Es posible que necesites desplegar un nuevo manager para usar el nuevo oraculo");
        }
        
        vm.stopBroadcast();
        
        console.log("=== Actualizacian del orsculo completada ===");
        console.log("Nueva direccion del oraculo:", newOracleAddress);
        console.log("Nueva direccion del calculador:", newCalculatorAddress);
        console.log("");
        console.log("IMPORTANTE: Verifica que la tasa VCOP/COP ahora es 1:1");
    }
    
    // Función auxiliar para intentar actualizar la referencia del oráculo
    function updateOracleReferenceInManager(VCOPCollateralManager manager, address newOracle) external {
        // Esta función es un placeholder - el contrato actual probablemente no tiene
        // un método para actualizar el oráculo después de la inicialización
        revert("Metodo no implementado en el contrato actual");
    }
} 