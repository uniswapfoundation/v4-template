// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {VCOPOracle} from "src/VCOPOracle.sol";

/**
 * @title DeployVCOPOracle
 * @notice Script para desplegar y configurar el oraculo VCOP que usa Uniswap v4
 */
contract DeployVCOPOracle is Script {
    // Parametros de configuracion - Direcciones de Base Sepolia
    
    // Pool Manager
    address constant POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
    
    // Tokens
    address constant VCOP_ADDRESS = 0xd16Ee99c7EA2B30c13c3dC298EADEE00B870BBCC;
    address constant USDC_ADDRESS = 0xE7a4113a8a497DD72D29F35E188eEd7403e8B2E8;
    
    // Parametros del pool
    uint24 constant FEE = 3000; // 0.30%
    int24 constant TICK_SPACING = 60;
    address constant HOOK_ADDRESS = 0x866bf94370e8A7C9cDeAFb592C2ac62903e30040;
    
    // Tasa inicial USD-COP (1 USD = 4200 COP)
    uint256 constant INITIAL_USD_TO_COP_RATE = 4200e6;

    function run() public {
        vm.startBroadcast();
        
        // Desplegar el oraculo
        VCOPOracle oracle = new VCOPOracle(
            INITIAL_USD_TO_COP_RATE,
            POOL_MANAGER,
            VCOP_ADDRESS,
            USDC_ADDRESS,
            FEE,
            TICK_SPACING,
            HOOK_ADDRESS
        );
        
        // Actualizar las tasas desde el pool (para verificacion)
        (uint256 vcopToCopRate, uint256 vcopToUsdPrice) = oracle.updateRatesFromPool();
        
        console.log("VCOPOracle desplegado en:", address(oracle));
        console.log("Tasa USD/COP:", INITIAL_USD_TO_COP_RATE / 1e6);
        console.log("Precio VCOP/USD del pool:", vcopToUsdPrice / 1e6);
        console.log("Tasa VCOP/COP calculada:", vcopToCopRate / 1e6);
        
        vm.stopBroadcast();
    }
} 