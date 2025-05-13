// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

import {VCOPCollateralHook} from "../src/VcopCollateral/VCOPCollateralHook.sol";

/// @notice Script para minar y desplegar el hook VCOPCollateralHook
contract DeployVCOPCollateralHook is Script {
    // Dirección estándar del deployer CREATE2
    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    function run() public returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        address vcopAddress = vm.envAddress("VCOP_ADDRESS");
        address oracleAddress = vm.envAddress("ORACLE_ADDRESS");
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        address treasuryAddress = vm.addr(deployerPrivateKey); // Usar deployer como treasury por defecto
        
        // Flags para el hook (beforeSwap, afterSwap, afterAddLiquidity)
        uint160 hookFlags = uint160(
            Hooks.BEFORE_SWAP_FLAG | 
            Hooks.AFTER_SWAP_FLAG | 
            Hooks.AFTER_ADD_LIQUIDITY_FLAG
        );
        
        // Crear Currency para VCOP y USDC
        Currency vcopCurrency = Currency.wrap(vcopAddress);
        Currency usdcCurrency = Currency.wrap(usdcAddress);
        
        console2.log("Minando direccion del hook...");
        
        // Codificar argumentos del constructor
        bytes memory constructorArgs = abi.encode(
            IPoolManager(poolManagerAddress),
            address(0), // collateralManager se configurará después
            oracleAddress,
            vcopCurrency,
            usdcCurrency,
            treasuryAddress
        );
        
        // Usar HookMiner para encontrar una dirección válida
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            hookFlags,
            type(VCOPCollateralHook).creationCode,
            constructorArgs
        );
        
        console2.log("Direccion encontrada:", hookAddress);
        console2.log("Con salt:", vm.toString(salt));
        
        // Broadcast transaction para desplegar el hook
        vm.startBroadcast(deployerPrivateKey);
        
        // Desplegar el hook usando CREATE2 con el salt minado
        VCOPCollateralHook hook = new VCOPCollateralHook{salt: salt}(
            IPoolManager(poolManagerAddress),
            address(0), // collateralManager se configurará después
            oracleAddress,
            vcopCurrency,
            usdcCurrency,
            treasuryAddress
        );
        
        // Verificar que se desplegó en la dirección esperada
        require(address(hook) == hookAddress, "Error en la direccion del hook");
        
        console2.log("VCOPCollateralHook desplegado en:", address(hook));
        
        vm.stopBroadcast();
        
        // Retornar la dirección del hook para que pueda ser usada por el script principal
        return address(hook);
    }
} 