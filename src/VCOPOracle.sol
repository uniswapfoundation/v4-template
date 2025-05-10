// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "v4-core/lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title VCOPOracle
 * @notice Oráculo mock simple para simular la entrega del precio de VCOP
 */
contract VCOPOracle is Ownable {
    // Precio actual de VCOP en USD (con 18 decimales)
    // 1 USD = 1e18
    uint256 private _price = 1e18;

    // Evento emitido cuando se actualiza el precio
    event PriceUpdated(uint256 oldPrice, uint256 newPrice);

    /**
     * @dev Constructor que inicializa el oráculo con un precio inicial
     * @param initialPrice El precio inicial (en formato 18 decimales)
     */
    constructor(uint256 initialPrice) Ownable(msg.sender) {
        if (initialPrice > 0) {
            _price = initialPrice;
        }
    }

    /**
     * @dev Obtiene el precio actual de VCOP
     * @return El precio actual en formato de 18 decimales
     */
    function getPrice() external view returns (uint256) {
        return _price;
    }

    /**
     * @dev Actualiza el precio manualmente (solo el propietario)
     * @param newPrice El nuevo precio a establecer (en formato 18 decimales)
     */
    function setPrice(uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Price must be greater than zero");
        
        uint256 oldPrice = _price;
        _price = newPrice;
        
        emit PriceUpdated(oldPrice, newPrice);
    }

    /**
     * @dev Simula un aumento de precio por un porcentaje específico
     * @param percentage El porcentaje de aumento (con 18 decimales, ej: 5% = 5e16)
     */
    function simulatePriceIncrease(uint256 percentage) external onlyOwner {
        require(percentage > 0, "Percentage must be greater than zero");
        
        uint256 oldPrice = _price;
        uint256 increase = (_price * percentage) / 1e18;
        _price += increase;
        
        emit PriceUpdated(oldPrice, _price);
    }

    /**
     * @dev Simula una disminución de precio por un porcentaje específico
     * @param percentage El porcentaje de disminución (con 18 decimales, ej: 5% = 5e16)
     */
    function simulatePriceDecrease(uint256 percentage) external onlyOwner {
        require(percentage > 0, "Percentage must be greater than zero");
        require(percentage < 1e18, "Percentage must be less than 100%");
        
        uint256 oldPrice = _price;
        uint256 decrease = (_price * percentage) / 1e18;
        _price -= decrease;
        
        emit PriceUpdated(oldPrice, _price);
    }
} 