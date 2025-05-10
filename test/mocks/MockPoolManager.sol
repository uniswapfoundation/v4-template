// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";

/**
 * @title MockPoolManager
 * @notice Mock implementation of IPoolManager for testing purposes
 */
contract MockPoolManager {
    // Este es un contrato mock simple para pruebas, no implementa toda la funcionalidad de IPoolManager
    // Solo lo necesario para que nuestro test funcione sin validaciones de hooks
    
    bool public initialized;
    mapping(PoolId => bool) public pools;
    
    function initialize(Currency, Currency, uint24, int24, address) external returns (PoolId) {
        initialized = true;
        return PoolId.wrap(bytes32(0));
    }
    
    // Implementa cualquier otra función necesaria para pasar los tests...
} 