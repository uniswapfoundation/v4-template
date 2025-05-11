// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {VCOPRebased} from "../src/VCOPRebased.sol";
import {VCOPOracle} from "../src/VCOPOracle.sol";
import {VCOPRebaseHook} from "../src/VCOPRebaseHook.sol";

/**
 * @title TestVCOPSystem
 * @notice Script para probar el sistema VCOP, interactuando con los contratos ya desplegados
 * y verificando el mecanismo de rebase
 */
contract TestVCOPSystem is Script {

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address vcopAddress = vm.envOr("VCOP_ADDRESS", address(0));
        address oracleAddress = vm.envOr("ORACLE_ADDRESS", address(0));
        address hookAddress = vm.envOr("HOOK_ADDRESS", address(0));
        
        // Verificar direcciones
        require(vcopAddress != address(0), "VCOP_ADDRESS no configurada");
        require(oracleAddress != address(0), "ORACLE_ADDRESS no configurada");
        require(hookAddress != address(0), "HOOK_ADDRESS no configurada");
        
        // Instanciar contratos (solo para verificar)
        VCOPRebased vcop = VCOPRebased(vcopAddress);
        VCOPOracle oracle = VCOPOracle(oracleAddress);
        VCOPRebaseHook hook = VCOPRebaseHook(hookAddress);
        
        // Imprimir informacion del sistema
        console2.log("=== Informacion del sistema VCOP ===");
        console2.log("Direccion VCOP:", vcopAddress);
        console2.log("Direccion Oracle:", oracleAddress);
        console2.log("Direccion Hook:", hookAddress);
        
        // Obtener informacion del estado actual
        uint256 totalSupply = vcop.totalSupply();
        uint256 vcopToCopRate = oracle.getVcopToCopRate();
        uint256 rebaseInterval = hook.rebaseInterval();
        
        console2.log("Suministro total actual:", totalSupply);
        console2.log("Tasa VCOP/COP:", vcopToCopRate);
        console2.log("Intervalo de rebase:", rebaseInterval);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Simular un cambio en el precio para provocar un rebase
        console2.log("=== Simulando cambio de precio para activar rebase ===");
        
        // Cambiar el precio a 1.1 COP por VCOP (por encima del umbral de expansion) - 110e4
        oracle.setVcopToCopRate(110e4);
        
        // Obtener nueva tasa
        uint256 newRate = oracle.getVcopToCopRate();
        console2.log("Nueva tasa VCOP/COP:", newRate);
        
        // Ejecutar un rebase manualmente 
        console2.log("=== Ejecutando rebase manualmente ===");
        uint256 newSupply = hook.executeRebase();
        
        console2.log("Nuevo suministro total:", newSupply);
        
        vm.stopBroadcast();
        
        // Imprimir mensaje final
        console2.log("=== Prueba completada ===");
        console2.log("Revisa los logs de eventos en la transaccion para ver el proceso de rebase completo");
    }
} 