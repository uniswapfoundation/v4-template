// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/**
 * @title ObtenerUSDCTest
 * @notice Script para obtener USDC de prueba para realizar operaciones de swap
 */
contract ObtenerUSDCTest is Script {
    // USDC de prueba - dirección actualizada
    address constant USDC_ADDRESS = 0x451CfC39fd0ED23F36D76AE6D53dF35D1457e756;
    // Cantidad a solicitar (con 6 decimales)
    uint256 constant CANTIDAD = 100 * 10**6; // 100 USDC
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        console.log("Obteniendo USDC de prueba para:", deployerAddress);
        
        // Antes de iniciar, obtenemos el balance actual
        IERC20 usdc = IERC20(USDC_ADDRESS);
        uint256 balanceInicial = usdc.balanceOf(deployerAddress);
        console.log("Balance USDC inicial:", balanceInicial / 10**6);

        vm.startBroadcast(deployerPrivateKey);
        
        // Intentar llamar a la función mint del contrato MockERC20
        MockERC20(USDC_ADDRESS).mint(deployerAddress, CANTIDAD);
        
        vm.stopBroadcast();
        
        // Verificamos el balance actualizado
        uint256 balanceFinal = usdc.balanceOf(deployerAddress);
        console.log("Balance USDC final:", balanceFinal / 10**6);
        console.log("USDC recibidos:", (balanceFinal - balanceInicial) / 10**6);
    }
} 