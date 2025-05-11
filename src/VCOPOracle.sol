// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "v4-core/lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title VCOPOracle
 * @notice Oráculo para proveer precio de VCOP en relación al peso colombiano (COP) y dólar (USD)
 */
contract VCOPOracle is Ownable {
    // Precio del dólar en pesos colombianos (con 18 decimales)
    // 4200 COP = 1 USD, entonces 4200e18
    uint256 private _usdToCopRate = 4200e18;
    
    // Factor de conversión VCOP a COP (con 18 decimales)
    // 1 VCOP = 1 COP inicialmente, entonces 1e18
    uint256 private _vcopToCopRate = 1e18;

    // Eventos emitidos cuando se actualizan los precios
    event UsdToCopRateUpdated(uint256 oldRate, uint256 newRate);
    event VcopToCopRateUpdated(uint256 oldRate, uint256 newRate);

    /**
     * @dev Constructor que inicializa el oráculo con tasas iniciales
     * @param initialUsdToCopRate La tasa inicial USD/COP (en formato 18 decimales)
     */
    constructor(uint256 initialUsdToCopRate) Ownable(msg.sender) {
        if (initialUsdToCopRate > 0) {
            _usdToCopRate = initialUsdToCopRate;
        }
    }

    /**
     * @dev Obtiene la tasa de cambio USD a COP
     * @return La tasa en formato de 18 decimales (ej: 4200e18 para 4200 COP por 1 USD)
     */
    function getUsdToCopRate() external view returns (uint256) {
        return _usdToCopRate;
    }

    /**
     * @dev Obtiene la tasa de cambio VCOP a COP
     * @return La tasa en formato de 18 decimales (ej: 1e18 para 1:1)
     */
    function getVcopToCopRate() external view returns (uint256) {
        return _vcopToCopRate;
    }
    
    /**
     * @dev Obtiene el precio de VCOP en USD
     * @return El precio en formato de 18 decimales
     */
    function getVcopToUsdPrice() external view returns (uint256) {
        // VCOP/USD = (VCOP/COP) * (COP/USD) = (VCOP/COP) / (USD/COP)
        return (_vcopToCopRate * 1e18) / _usdToCopRate;
    }
    
    /**
     * @dev Obtiene el precio de VCOP para el mecanismo de rebase
     * Este método se mantiene compatible con el sistema de rebase existente
     * @return El precio en formato de 18 decimales
     */
    function getPrice() external view returns (uint256) {
        // Para mantener compatibilidad con el sistema de rebase existente
        // Devolvemos la relación VCOP/COP que idealmente es 1:1
        return _vcopToCopRate;
    }

    /**
     * @dev Actualiza la tasa USD a COP manualmente (solo el propietario)
     * @param newRate La nueva tasa a establecer (en formato 18 decimales)
     */
    function setUsdToCopRate(uint256 newRate) external onlyOwner {
        require(newRate > 0, "Rate must be greater than zero");
        
        uint256 oldRate = _usdToCopRate;
        _usdToCopRate = newRate;
        
        emit UsdToCopRateUpdated(oldRate, newRate);
    }
    
    /**
     * @dev Actualiza la tasa VCOP a COP manualmente (solo el propietario)
     * @param newRate La nueva tasa a establecer (en formato 18 decimales)
     */
    function setVcopToCopRate(uint256 newRate) external onlyOwner {
        require(newRate > 0, "Rate must be greater than zero");
        
        uint256 oldRate = _vcopToCopRate;
        _vcopToCopRate = newRate;
        
        emit VcopToCopRateUpdated(oldRate, newRate);
    }

    /**
     * @dev Simula un aumento de la tasa USD/COP por un porcentaje específico
     * @param percentage El porcentaje de aumento (con 18 decimales, ej: 5% = 5e16)
     */
    function simulateUsdToCopRateIncrease(uint256 percentage) external onlyOwner {
        require(percentage > 0, "Percentage must be greater than zero");
        
        uint256 oldRate = _usdToCopRate;
        uint256 increase = (_usdToCopRate * percentage) / 1e18;
        _usdToCopRate += increase;
        
        emit UsdToCopRateUpdated(oldRate, _usdToCopRate);
    }

    /**
     * @dev Simula una disminución de la tasa USD/COP por un porcentaje específico
     * @param percentage El porcentaje de disminución (con 18 decimales, ej: 5% = 5e16)
     */
    function simulateUsdToCopRateDecrease(uint256 percentage) external onlyOwner {
        require(percentage > 0, "Percentage must be greater than zero");
        require(percentage < 1e18, "Percentage must be less than 100%");
        
        uint256 oldRate = _usdToCopRate;
        uint256 decrease = (_usdToCopRate * percentage) / 1e18;
        _usdToCopRate -= decrease;
        
        emit UsdToCopRateUpdated(oldRate, _usdToCopRate);
    }
} 