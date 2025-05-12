// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {VCOPPriceCalculator} from "../src/VCOPPriceCalculator.sol";
import {VCOPOracle} from "../src/VCOPOracle.sol";

contract VerifyVCOPPrice is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Addresses from the previous deployment
        address calculatorAddress = 0x148a8F284091115eC9685AfAa49B0Ab94569Ac80;
        address oracleAddress = 0xF29273213570443bf974469aAe3EfEa26C3c7CF0;
        address vcopAddress = 0xAA21DF6F00Bf8783b4e9159Ea47E7E3809860f8C;
        address usdcAddress = 0x61D605815094CD07Bc3f4Eb16cF64D4b2C459499;

        vm.startBroadcast(deployerPrivateKey);
        
        console.log("=== Verificando precios VCOP ===");
        console.log("Direccion calculador:", calculatorAddress);
        console.log("Direccion oraculo:", oracleAddress);
        console.log("Direccion VCOP:", vcopAddress);
        console.log("Direccion USDC:", usdcAddress);
        
        // Crear instancias para llamadas
        VCOPPriceCalculator calculator = VCOPPriceCalculator(calculatorAddress);
        VCOPOracle oracle = VCOPOracle(oracleAddress);
        
        console.log("=== Informacion del calculador ===");
        console.log("USD/COP rate:", calculator.usdToCopRate());
        console.log("VCOP es token0:", calculator.isVCOPToken0());
        
        // Intentar leer paridad directamente (view function)
        try calculator.isVcopAtParity() returns (bool parity) {
            console.log("Paridad desde calculador:", parity);
        } catch {
            console.log("Error al verificar paridad desde calculador");
        }
        
        // Intentar leer oracle en modo view (no state changes)
        try this.checkOracleParityView(oracleAddress) returns (bool parity) {
            console.log("Paridad desde oraculo (view):", parity);
        } catch {
            console.log("Error al verificar paridad desde oraculo (view)");
        }
        
        // Intentar actualizar tasas (state-changing call)
        console.log("=== Actualizando tasas desde oraculo ===");
        try oracle.updateRatesFromPool() returns (uint256 vcopToCopRate, uint256 vcopToUsdPrice) {
            console.log("Tasa VCOP/COP actualizada:", vcopToCopRate);
            console.log("VCOP/COP como decimal:", vcopToCopRate / 1e6);
            console.log("Precio VCOP/USD del pool:", vcopToUsdPrice);
        } catch {
            console.log("Error al actualizar tasas desde el oraculo");
        }
        
        vm.stopBroadcast();
    }
    
    // Helper para llamadas view
    function checkOracleParityView(address oracleAddress) external view returns (bool) {
        VCOPOracle oracle = VCOPOracle(oracleAddress);
        return oracle.isVcopAtParity();
    }
} 