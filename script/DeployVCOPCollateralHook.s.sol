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
    
    // Direcciones hardcodeadas como fallback
    address constant DEPLOYED_USDC_ADDRESS = 0x836C5578Dfa06EB3fCA056bdbB998433ddD12d6B;
    address constant DEPLOYED_VCOP_ADDRESS = 0x180e67aE4a941E9213425b962b06b8578B2fEf5C;
    address constant DEPLOYED_ORACLE_ADDRESS = 0x45C52AF0B64C053E0DC193369facF3c1a8718A3a;
    address constant DEPLOYED_COLLATERAL_MANAGER_ADDRESS = 0x962e3b4CA8587B59475b8204137Fa06cB7302d87;

    function run() public returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        // Obtener direcciones usando fallback hardcodeado si la variable de entorno no está disponible
        address poolManagerAddress;
        try vm.envAddress("POOL_MANAGER_ADDRESS") returns (address addr) {
            poolManagerAddress = addr;
        } catch {
            revert("POOL_MANAGER_ADDRESS no encontrada en variables de entorno");
        }
        
        // Obtener VCOP address o usar hardcodeada
        address vcopAddress;
        try vm.envAddress("VCOP_ADDRESS") returns (address addr) {
            if(addr != address(0)) {
                vcopAddress = addr;
                console2.log("VCOP address cargada de variables de entorno");
            } else {
                vcopAddress = DEPLOYED_VCOP_ADDRESS;
                console2.log("VCOP address usando valor hardcodeado");
            }
        } catch {
            vcopAddress = DEPLOYED_VCOP_ADDRESS;
            console2.log("VCOP address usando valor hardcodeado");
        }
        
        // Obtener Oracle address o usar hardcodeada
        address oracleAddress;
        try vm.envAddress("ORACLE_ADDRESS") returns (address addr) {
            if(addr != address(0)) {
                oracleAddress = addr;
                console2.log("Oracle address cargada de variables de entorno");
            } else {
                oracleAddress = DEPLOYED_ORACLE_ADDRESS;
                console2.log("Oracle address usando valor hardcodeado");
            }
        } catch {
            oracleAddress = DEPLOYED_ORACLE_ADDRESS;
            console2.log("Oracle address usando valor hardcodeado");
        }
        
        // Obtener USDC address o usar hardcodeada
        address usdcAddress;
        try vm.envAddress("USDC_ADDRESS") returns (address addr) {
            if(addr != address(0)) {
                usdcAddress = addr;
                console2.log("USDC address cargada de variables de entorno");
            } else {
                usdcAddress = DEPLOYED_USDC_ADDRESS;
                console2.log("USDC address usando valor hardcodeado");
            }
        } catch {
            usdcAddress = DEPLOYED_USDC_ADDRESS;
            console2.log("USDC address usando valor hardcodeado");
        }
        
        // Obtener Collateral Manager address o usar hardcodeada
        address collateralManagerAddress;
        try vm.envAddress("COLLATERAL_MANAGER_ADDRESS") returns (address addr) {
            if(addr != address(0)) {
                collateralManagerAddress = addr;
                console2.log("CollateralManager address cargada de variables de entorno");
            } else {
                collateralManagerAddress = DEPLOYED_COLLATERAL_MANAGER_ADDRESS;
                console2.log("CollateralManager address usando valor hardcodeado");
            }
        } catch {
            collateralManagerAddress = DEPLOYED_COLLATERAL_MANAGER_ADDRESS;
            console2.log("CollateralManager address usando valor hardcodeado");
        }
        
        // Usar deployer como treasury por defecto
        address treasuryAddress = deployerAddress;
        
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
        
        // Log addresses being used
        console2.log("Usando las siguientes direcciones:");
        console2.log("USDC:", usdcAddress);
        console2.log("VCOP:", vcopAddress);
        console2.log("Oracle:", oracleAddress);
        console2.log("CollateralManager:", collateralManagerAddress);
        
        // Codificar argumentos del constructor
        bytes memory constructorArgs = abi.encode(
            IPoolManager(poolManagerAddress),
            collateralManagerAddress,
            oracleAddress,
            vcopCurrency,
            usdcCurrency,
            treasuryAddress,
            deployerAddress
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
            collateralManagerAddress,
            oracleAddress,
            vcopCurrency,
            usdcCurrency,
            treasuryAddress,
            deployerAddress
        );
        
        // Verificar que se desplegó en la dirección esperada
        require(address(hook) == hookAddress, "Error en la direccion del hook");
        
        console2.log("VCOPCollateralHook desplegado en:", address(hook));
        console2.log("Owner establecido como el deployer:", deployerAddress);
        
        vm.stopBroadcast();
        
        // Retornar la dirección del hook para que pueda ser usada por el script principal
        return address(hook);
    }
} 