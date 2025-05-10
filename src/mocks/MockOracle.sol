// SPDX-License-Identifier: Unlicense
// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/IOracle.sol";

/**
 * @title MockOracle - Oracle para la tasa COP/USD
 */
contract MockOracle is IOracle {
    // Valor por defecto: 4200 COP = 1 USD, con 18 decimales
    uint256 private _usdToCopRate = 4200e18;
    
    // Factor de conversión para mantener los 18 decimales al convertir
    uint256 private constant PRICE_PRECISION = 1e18;
    
    /// @notice Establece una nueva tasa COP/USD para pruebas
    /// @param newRate Nueva tasa (ej: 4200e18 significa 4200 COP = 1 USD)
    function setUsdToCopRate(uint256 newRate) external {
        require(newRate > 0, "Rate must be positive");
        _usdToCopRate = newRate;
    }
    
    /// @notice Retorna el precio de la stablecoin en COP (normalmente 1 COP)
    /// @return Precio en COP con 18 decimales
    function getPrice() external view override returns (uint256) {
        // La tasa base oficial de VCOP es 1:1 con el peso colombiano
        // Este oráculo utiliza la tasa USD/COP para calcular el valor de VCOP en COP
        
        // Ejemplo: si el tipo de cambio es 4200 COP/USD, entonces 1 VCOP debe valer 1 COP
        // Si el USD se fortalece (ej: 4400 COP/USD), 1 VCOP sigue valiendo 1 COP
        // Si el USD se debilita (ej: 4000 COP/USD), 1 VCOP sigue valiendo 1 COP
        
        // En este oráculo de prueba, simulamos desviaciones del valor ideal:
        // - Si _usdToCopRate < 4200, VCOP vale más de 1 COP (inflación del VCOP)
        // - Si _usdToCopRate > 4200, VCOP vale menos de 1 COP (deflación del VCOP)
        
        uint256 baseRate = 4200e18; // Tasa base oficial: 4200 COP = 1 USD
        return (baseRate * PRICE_PRECISION) / _usdToCopRate;
    }
    
    /// @notice Obtiene la tasa de cambio actual
    /// @return Tasa COP/USD con 18 decimales
    function getUsdToCopRate() external view returns (uint256) {
        return _usdToCopRate;
    }
} 