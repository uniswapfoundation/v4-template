// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title VCOPSwapConfig
 * @notice Configuración para operaciones de swap con VCOP
 * @dev Edite este archivo para modificar parámetros de operación
 */
contract VCOPSwapConfig {
    // Modo de operación: true = COMPRAR VCOP, false = VENDER VCOP
    bool private constant _COMPRAR_VCOP = true;
    
    // Cantidad a intercambiar (con 6 decimales)
    // Si COMPRAR_VCOP = true: cantidad de USDC a gastar
    // Si COMPRAR_VCOP = false: cantidad de VCOP a vender
    uint256 private constant _CANTIDAD = 100 * 10**6; // 100 USDC o 100 VCOP
    
    // OPCIONAL: Slippage máximo (porcentaje * 100), por defecto ilimitado
    // Ejemplo: 50 = 0.5%, 100 = 1%, 1000 = 10%
    // Poner en 0 para impacto ilimitado
    uint16 private constant _SLIPPAGE_MAX = 500; // 5%
    
    // ======== Funciones para acceder a la configuración ========
    
    function COMPRAR_VCOP() public pure returns (bool) {
        return _COMPRAR_VCOP;
    }
    
    function CANTIDAD() public pure returns (uint256) {
        return _CANTIDAD;
    }
    
    function SLIPPAGE_MAX() public pure returns (uint16) {
        return _SLIPPAGE_MAX;
    }
} 