// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/**
 * @title DeployMockUSDC
 * @notice Script para desplegar un token que simula USDC para pruebas
 * Se utiliza antes del despliegue principal para crear un ambiente de prueba completo
 */
contract DeployMockUSDC is Script {
    // Constantes
    uint8 constant USDC_DECIMALS = 6;
    uint256 constant INITIAL_SUPPLY = 10_000_000 * 6**USDC_DECIMALS; // 10,000,000 USDC

    function run() public returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        console.log("=== Desplegando Mock USDC ===");
        console.log("Direccion del desplegador:", deployerAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Desplegar el token MockUSDC con 6 decimales
        MockERC20 mockUSDC = new MockERC20("USD Coin", "USDC", USDC_DECIMALS);
        
        // Acuñar suministro inicial al desplegador
        mockUSDC.mint(deployerAddress, INITIAL_SUPPLY);
        
        vm.stopBroadcast();
        
        console.log("Mock USDC desplegado en:", address(mockUSDC));
        console.log("Suministro inicial:", INITIAL_SUPPLY / 10**USDC_DECIMALS, "USDC");
        
        // Guardar la dirección en una variable de entorno para uso posterior
        vm.setEnv("MOCK_USDC_ADDRESS", vm.toString(address(mockUSDC)));
        
        return address(mockUSDC);
    }
} 