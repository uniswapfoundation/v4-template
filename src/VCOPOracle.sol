// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "v4-core/lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {console2 as console} from "forge-std/console2.sol"; // Usar console2 en lugar de console

/**
 * @title VCOPOracle
 * @notice Oráculo para proveer precio de VCOP en relación al peso colombiano (COP) y dólar (USD)
 * @dev Usa 6 decimales para mantener consistencia con VCOP y USDC
 */
contract VCOPOracle is Ownable {
    // Precio del dólar en pesos colombianos (con 6 decimales)
    // 4200 COP = 1 USD, entonces 4200e6
    uint256 private _usdToCopRate = 4200e6;
    
    // Factor de conversión VCOP a COP (con 6 decimales)
    // 1 VCOP = 1 COP inicialmente, entonces 1e6
    uint256 private _vcopToCopRate = 1e6;

    // Eventos emitidos cuando se actualizan los precios
    event UsdToCopRateUpdated(uint256 oldRate, uint256 newRate);
    event VcopToCopRateUpdated(uint256 oldRate, uint256 newRate);
    
    // Nuevos eventos para seguimiento detallado
    event PriceRequested(address requester, string rateType);
    event PriceProvided(address requester, string rateType, uint256 rate);

    /**
     * @dev Constructor que inicializa el oráculo con tasas iniciales
     * @param initialUsdToCopRate La tasa inicial USD/COP (en formato 6 decimales)
     */
    constructor(uint256 initialUsdToCopRate) Ownable(msg.sender) {
        if (initialUsdToCopRate > 0) {
            _usdToCopRate = initialUsdToCopRate;
        }
        console.log("VCOPOracle inicializado");
        console.log("Tasa inicial USD/COP:", _usdToCopRate);
        console.log("Tasa inicial VCOP/COP:", _vcopToCopRate);
    }

    /**
     * @dev Obtiene la tasa de cambio USD a COP
     * @return La tasa en formato de 6 decimales (ej: 4200e6 para 4200 COP por 1 USD)
     */
    function getUsdToCopRate() external returns (uint256) {
        console.log("Consulta de tasa USD/COP por:", msg.sender);
        console.log("Tasa USD/COP actual:", _usdToCopRate);
        
        emit PriceRequested(msg.sender, "USD/COP");
        emit PriceProvided(msg.sender, "USD/COP", _usdToCopRate);
        
        return _usdToCopRate;
    }

    /**
     * @dev Obtiene la tasa de cambio VCOP a COP
     * @return La tasa en formato de 6 decimales (ej: 1e6 para 1:1)
     */
    function getVcopToCopRate() external returns (uint256) {
        console.log("Consulta de tasa VCOP/COP por:", msg.sender);
        console.log("Tasa VCOP/COP actual:", _vcopToCopRate);
        
        emit PriceRequested(msg.sender, "VCOP/COP");
        emit PriceProvided(msg.sender, "VCOP/COP", _vcopToCopRate);
        
        return _vcopToCopRate;
    }
    
    /**
     * @dev Obtiene el precio de VCOP en USD
     * @return El precio en formato de 6 decimales
     */
    function getVcopToUsdPrice() external returns (uint256) {
        // VCOP/USD = (VCOP/COP) * (COP/USD) = (VCOP/COP) / (USD/COP)
        uint256 vcopToUsdPrice = (_vcopToCopRate * 1e6) / _usdToCopRate;
        
        console.log("Consulta de precio VCOP/USD por:", msg.sender);
        console.log("Usando tasa VCOP/COP:", _vcopToCopRate);
        console.log("Usando tasa USD/COP:", _usdToCopRate);
        console.log("Precio VCOP/USD calculado:", vcopToUsdPrice);
        
        emit PriceRequested(msg.sender, "VCOP/USD");
        emit PriceProvided(msg.sender, "VCOP/USD", vcopToUsdPrice);
        
        return vcopToUsdPrice;
    }
    
    /**
     * @dev Obtiene el precio de VCOP para el mecanismo de rebase
     * Este método se mantiene compatible con el sistema de rebase existente
     * @return El precio en formato de 6 decimales
     */
    function getPrice() external returns (uint256) {
        // Para mantener compatibilidad con el sistema de rebase existente
        // Devolvemos la relación VCOP/COP que idealmente es 1:1
        console.log("Consulta de precio para rebase por:", msg.sender);
        console.log("Devolviendo tasa VCOP/COP:", _vcopToCopRate);
        
        emit PriceRequested(msg.sender, "REBASE");
        emit PriceProvided(msg.sender, "REBASE", _vcopToCopRate);
        
        return _vcopToCopRate;
    }

    /**
     * @dev Actualiza la tasa USD a COP manualmente (solo el propietario)
     * @param newRate La nueva tasa a establecer (en formato 6 decimales)
     */
    function setUsdToCopRate(uint256 newRate) external onlyOwner {
        require(newRate > 0, "Rate must be greater than zero");
        
        uint256 oldRate = _usdToCopRate;
        _usdToCopRate = newRate;
        
        console.log("Tasa USD/COP actualizada por:", msg.sender);
        console.log("Tasa anterior:", oldRate);
        console.log("Nueva tasa:", newRate);
        
        emit UsdToCopRateUpdated(oldRate, newRate);
    }
    
    /**
     * @dev Actualiza la tasa VCOP a COP manualmente (solo el propietario)
     * @param newRate La nueva tasa a establecer (en formato 6 decimales)
     */
    function setVcopToCopRate(uint256 newRate) external onlyOwner {
        require(newRate > 0, "Rate must be greater than zero");
        
        uint256 oldRate = _vcopToCopRate;
        _vcopToCopRate = newRate;
        
        console.log("Tasa VCOP/COP actualizada por:", msg.sender);
        console.log("Tasa anterior:", oldRate);
        console.log("Nueva tasa:", newRate);
        
        emit VcopToCopRateUpdated(oldRate, newRate);
    }

    /**
     * @dev Simula un aumento de la tasa USD/COP por un porcentaje específico
     * @param percentage El porcentaje de aumento (con 6 decimales, ej: 5% = 5e4)
     */
    function simulateUsdToCopRateIncrease(uint256 percentage) external onlyOwner {
        require(percentage > 0, "Percentage must be greater than zero");
        
        uint256 oldRate = _usdToCopRate;
        uint256 increase = (_usdToCopRate * percentage) / 1e6;
        _usdToCopRate += increase;
        
        console.log("Simulacion de aumento USD/COP por:", msg.sender);
        console.log("Porcentaje de aumento:", percentage);
        console.log("Tasa anterior:", oldRate);
        console.log("Nueva tasa:", _usdToCopRate);
        console.log("Incremento absoluto:", increase);
        
        emit UsdToCopRateUpdated(oldRate, _usdToCopRate);
    }

    /**
     * @dev Simula una disminución de la tasa USD/COP por un porcentaje específico
     * @param percentage El porcentaje de disminución (con 6 decimales, ej: 5% = 5e4)
     */
    function simulateUsdToCopRateDecrease(uint256 percentage) external onlyOwner {
        require(percentage > 0, "Percentage must be greater than zero");
        require(percentage < 1e6, "Percentage must be less than 100%");
        
        uint256 oldRate = _usdToCopRate;
        uint256 decrease = (_usdToCopRate * percentage) / 1e6;
        _usdToCopRate -= decrease;
        
        console.log("Simulacion de disminucion USD/COP por:", msg.sender);
        console.log("Porcentaje de disminucion:", percentage);
        console.log("Tasa anterior:", oldRate);
        console.log("Nueva tasa:", _usdToCopRate);
        console.log("Decremento absoluto:", decrease);
        
        emit UsdToCopRateUpdated(oldRate, _usdToCopRate);
    }
} 