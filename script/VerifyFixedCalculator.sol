// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {VCOPPriceCalculatorFixed} from "../src/VCOPPriceCalculatorFixed.sol";

contract VerifyFixedCalculator is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Leer la dirección del calculador fijo - ya sea de una variable de entorno
        // o usar la predeterminada si aún no está desplegado
        address calculatorAddress;
        try vm.envOr("FIXED_CALCULATOR_ADDRESS", address(0)) returns (address addr) {
            if (addr != address(0)) {
                calculatorAddress = addr;
            } else {
                revert("Calculador no desplegado. Ejecute DeployFixedCalculator primero");
            }
        } catch {
            revert("Calculador no desplegado. Ejecute DeployFixedCalculator primero");
        }

        console.log("=== Verificando calculador de precios corregido ===");
        console.log("Direccion del calculador:", calculatorAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        VCOPPriceCalculatorFixed calculator = VCOPPriceCalculatorFixed(calculatorAddress);
        
        // Verificar datos básicos
        console.log("USD/COP Rate:", calculator.usdToCopRate());
        console.log("VCOP es token0:", calculator.isVCOPToken0());
        console.log("Valor predeterminado VCOP/USD:", calculator.DEFAULT_VCOP_USD_PRICE());
        
        // Intentar obtener el precio USD
        try calculator.getVcopToUsdPriceFromPool() returns (
            uint256 vcopToUsdPrice, 
            int24 tick, 
            bool hasError
        ) {
            console.log("=== Resultados de getVcopToUsdPriceFromPool ===");
            console.log("VCOP/USD Price:", vcopToUsdPrice);
            console.log("Tick:", tick);
            console.log("Hubo errores:", hasError);
            
            if (hasError) {
                console.log("Se uso el valor predeterminado debido a errores");
            }
        } catch {
            console.log("Error al llamar getVcopToUsdPriceFromPool");
        }
        
        // Intentar obtener el precio COP
        try calculator.getVcopToCopPrice() returns (
            uint256 vcopToCopPrice, 
            int24 tick, 
            bool hasError
        ) {
            console.log("=== Resultados de getVcopToCopPrice ===");
            console.log("VCOP/COP Price:", vcopToCopPrice);
            console.log("VCOP/COP como decimal:", vcopToCopPrice / 1e6);
            console.log("Tick:", tick);
            console.log("Hubo errores:", hasError);
        } catch {
            console.log("Error al llamar getVcopToCopPrice");
        }
        
        // Verificar la paridad
        try calculator.isVcopAtParity() returns (bool isAtParity) {
            console.log("=== Resultado de isVcopAtParity ===");
            console.log("En paridad 1:1:", isAtParity);
        } catch {
            console.log("Error al llamar isVcopAtParity");
        }
        
        // Verificar el cálculo completo
        try calculator.calculateAllPrices() returns (
            uint256 vcopToUsdPrice,
            uint256 vcopToCopPrice,
            int24 currentTick,
            bool isAtParity
        ) {
            console.log("=== Resultados de calculateAllPrices ===");
            console.log("VCOP/USD Price:", vcopToUsdPrice);
            console.log("VCOP/COP Price:", vcopToCopPrice);
            console.log("VCOP/COP como decimal:", vcopToCopPrice / 1e6);
            console.log("Tick actual:", currentTick);
            console.log("En paridad:", isAtParity);
        } catch {
            console.log("Error al llamar calculateAllPrices");
        }
        
        vm.stopBroadcast();
    }
} 