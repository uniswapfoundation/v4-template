// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {VCOPOracle} from "../src/VCOPOracle.sol";
import {VCOPPriceCalculatorFixed} from "../src/VCOPPriceCalculatorFixed.sol";

/**
 * @title UpdateVCOPOracle
 * @notice Script para actualizar el oraculo VCOP para usar el calculador de precios mejorado
 */
contract UpdateVCOPOracle is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Direcciones de contratos desplegados
        address oracleAddress = 0xF29273213570443bf974469aAe3EfEa26C3c7CF0;
        address fixedCalculatorAddress = 0xC4F73560B491b75739F24ad50c98bB402e653810;
        
        console.log("=== Actualizando VCOP Oracle ===");
        console.log("Direccion del oraculo:", oracleAddress);
        console.log("Nuevo calculador:", fixedCalculatorAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Instanciar el oráculo
        VCOPOracle oracle = VCOPOracle(oracleAddress);
        
        // Actualizar el calculador
        oracle.setPriceCalculator(fixedCalculatorAddress);
        
        console.log("Oracle actualizado para usar el calculador mejorado");
        
        // Verificar que el cambio fue efectivo
        // No podemos llamar a getVcopToUsdPriceFromPool directamente
        // pero podemos verificar si está en paridad
        bool isAtParity = oracle.isVcopAtParity();
        console.log("VCOP en paridad 1:1 segun el oraculo:", isAtParity);
        
        // Intentar actualizar las tasas
        try oracle.updateRatesFromPool() returns (uint256 vcopToCopRate, uint256 vcopToUsdPrice) {
            console.log("Tasas actualizadas exitosamente:");
            console.log("VCOP/COP:", vcopToCopRate);
            console.log("VCOP/COP como decimal:", vcopToCopRate / 1e6);
            console.log("VCOP/USD:", vcopToUsdPrice);
        } catch {
            console.log("Error al actualizar tasas - esto es normal si el pool no esta listo");
        }
        
        vm.stopBroadcast();
    }
} 