// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {VCOPPriceCalculatorFixed} from "../src/VCOPPriceCalculatorFixed.sol";

contract DeployFixedCalculator is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        address vcopAddress = 0xAA21DF6F00Bf8783b4e9159Ea47E7E3809860f8C;
        address usdcAddress = 0x61D605815094CD07Bc3f4Eb16cF64D4b2C459499;
        address hookAddress = 0xfc9783b1d606fc800a757b386c403801F2164040;
        uint24 fee = 3000; // 0.3%
        int24 tickSpacing = 60;
        uint256 usdToCopRate = 4200 * 1e6; // 4200 COP = 1 USD

        console.log("=== Desplegando calculador de precios corregido ===");
        console.log("Pool Manager:", poolManagerAddress);
        console.log("VCOP:", vcopAddress);
        console.log("USDC:", usdcAddress);
        console.log("Hook:", hookAddress);
        console.log("USD/COP Rate:", usdToCopRate);

        vm.startBroadcast(deployerPrivateKey);

        // Desplegar el calculador de precios con manejo mejorado de errores
        VCOPPriceCalculatorFixed calculator = new VCOPPriceCalculatorFixed(
            poolManagerAddress,
            vcopAddress,
            usdcAddress,
            fee,
            tickSpacing,
            hookAddress,
            usdToCopRate
        );

        console.log("Calculador de precios corregido desplegado en:", address(calculator));

        vm.stopBroadcast();

        // Guardar la dirección para uso futuro
        vm.setEnv("FIXED_CALCULATOR_ADDRESS", vm.toString(address(calculator)));
    }
} 