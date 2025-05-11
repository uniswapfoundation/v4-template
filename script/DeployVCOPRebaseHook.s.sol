// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

import {VCOPRebased} from "../src/VCOPRebased.sol";
import {VCOPOracle} from "../src/VCOPOracle.sol";
import {VCOPRebaseHook} from "../src/VCOPRebaseHook.sol";

/// @notice Script para minar y desplegar el hook de VCOPRebase con una dirección válida
contract DeployVCOPRebaseHook is Script {
    // Constante para el deployer de CREATE2
    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        address vcopAddress = vm.envAddress("VCOP_ADDRESS");
        address oracleAddress = vm.envAddress("ORACLE_ADDRESS");
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        
        // Define los flags para el hook (usamos afterSwap)
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);
        
        // Crear Currency para VCOP y USDC
        Currency vcopCurrency = Currency.wrap(vcopAddress);
        Currency usdcCurrency = Currency.wrap(usdcAddress);
        
        // Encode constructor arguments
        bytes memory constructorArgs = abi.encode(
            IPoolManager(poolManagerAddress),
            vcopAddress,
            oracleAddress,
            vcopCurrency,
            usdcCurrency
        );
        
        // Usar HookMiner para encontrar una dirección válida
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(VCOPRebaseHook).creationCode,
            constructorArgs
        );
        
        console.log("Mining hook address...");
        console.log("Found address:", hookAddress);
        console.log("With salt:", vm.toString(salt));
        
        // Broadcast transaction to deploy the hook
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the hook using CREATE2 with the mined salt
        VCOPRebaseHook hook = new VCOPRebaseHook{salt: salt}(
            IPoolManager(poolManagerAddress),
            vcopAddress,
            oracleAddress,
            vcopCurrency,
            usdcCurrency
        );
        
        // Verificar que se desplegó en la dirección esperada
        require(address(hook) == hookAddress, "Hook address mismatch");
        
        // Autorizar al hook para ejecutar rebases
        VCOPRebased(vcopAddress).setRebaser(address(hook), true);
        
        console.log("VCOPRebaseHook desplegado en:", address(hook));
        
        // Guardar la dirección del hook para el siguiente script
        vm.setEnv("HOOK_ADDRESS", vm.toString(address(hook)));
        
        vm.stopBroadcast();
    }
} 