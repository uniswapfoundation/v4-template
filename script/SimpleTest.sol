// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Script simplificado para probar el mecanismo de rebase de VCOP
// Ejecutar: forge script script/SimpleTest.sol:SimpleTest --via-ir --broadcast --fork-url https://sepolia.base.org

import {Script} from "forge-std/Script.sol";
import {VCOPRebased} from "../src/VCOPRebased.sol";
import {VCOPOracle} from "../src/VCOPOracle.sol";
import {VCOPRebaseHook} from "../src/VCOPRebaseHook.sol";

contract SimpleTest is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address vcopAddress = vm.envAddress("VCOP_ADDRESS");
        address oracleAddress = vm.envAddress("ORACLE_ADDRESS");
        address hookAddress = vm.envAddress("HOOK_ADDRESS");
        
        // Instanciar contratos
        VCOPRebased vcop = VCOPRebased(vcopAddress);
        VCOPOracle oracle = VCOPOracle(oracleAddress);
        VCOPRebaseHook hook = VCOPRebaseHook(hookAddress);
        
        // Obtener estado inicial
        uint256 initialSupply = vcop.totalSupply();
        uint256 initialRate = oracle.getVcopToCopRate();
        
        vm.startBroadcast(deployerPrivateKey);
        
        // En lugar de llamar a una función que no existe, usamos directamente
        // el mecanismo de rebase con el valor deseado
        uint256 newSupply = vcop.rebase(110e4); // Simular directamente una tasa de 1.1 COP por VCOP
        
        vm.stopBroadcast();
        
        // Los eventos emitidos mostrarán detalles del rebase en los logs de la transacción
    }
} 