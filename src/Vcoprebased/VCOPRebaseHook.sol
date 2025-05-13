// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

import {VCOPRebased} from "./VCOPRebased.sol";
import {VCOPOracle} from "./VCOPOracle.sol";
import {console2 as console} from "forge-std/console2.sol";

/**
 * @title VCOPRebaseHook
 * @notice Hook de Uniswap v4 que monitorea el precio de VCOP y ejecuta rebases automáticos
 * para mantener la paridad 1:1 con el peso colombiano (COP)
 */
contract VCOPRebaseHook is BaseHook {
    using PoolIdLibrary for PoolKey;

    // Token VCOP
    VCOPRebased public immutable vcop;
    
    // Oráculo de precio
    VCOPOracle public immutable oracle;
    
    // Periodo mínimo entre rebases (en segundos)
    uint256 public rebaseInterval = 1 hours;
    
    // Último timestamp de rebase
    uint256 public lastRebaseTime;
    
    // Currency ID del token VCOP
    Currency public vcopCurrency;
    
    // Currency ID del token USD de referencia (stablecoin)
    Currency public stablecoinCurrency;
    
    // Evento emitido cuando se ejecuta un rebase
    event RebaseExecuted(uint256 vcopToCopRate, uint256 newTotalSupply);
    
    // Evento emitido cuando se actualiza el intervalo de rebase
    event RebaseIntervalUpdated(uint256 oldInterval, uint256 newInterval);
    
    // Nuevos eventos para seguimiento detallado - actualizado el tipo a PoolId
    event SwapDetected(address caller, PoolId poolId);
    event VCOPPoolIdentified(PoolId poolId, bool isToken0);
    event RebaseEvaluated(uint256 currentTime, uint256 lastRebaseTime, uint256 rebaseInterval, bool willRebase);

    constructor(
        IPoolManager _poolManager, 
        address _vcop,
        address _oracle,
        Currency _vcopCurrency,
        Currency _stablecoinCurrency
    ) BaseHook(_poolManager) {
        vcop = VCOPRebased(_vcop);
        oracle = VCOPOracle(_oracle);
        vcopCurrency = _vcopCurrency;
        stablecoinCurrency = _stablecoinCurrency;
        lastRebaseTime = block.timestamp;
        
        console.log("VCOPRebaseHook inicializado");
        console.log("Direccion VCOP:", address(_vcop));
        console.log("Direccion Oracle:", address(_oracle));
        console.log("Intervalo inicial de rebase:", rebaseInterval);
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
    
    /**
     * @dev Cambia el intervalo mínimo entre rebases
     * @param newInterval El nuevo intervalo en segundos
     */
    function setRebaseInterval(uint256 newInterval) external {
        require(msg.sender == vcop.owner(), "Not authorized");
        
        uint256 oldInterval = rebaseInterval;
        rebaseInterval = newInterval;
        
        console.log("Intervalo de rebase cambiado de", oldInterval, "a", newInterval);
        
        emit RebaseIntervalUpdated(oldInterval, newInterval);
    }
    
    /**
     * @dev Ejecuta un rebase basado en el precio del oráculo
     * @return El nuevo suministro total
     */
    function executeRebase() public returns (uint256) {
        require(block.timestamp >= lastRebaseTime + rebaseInterval, "Rebase too soon");
        
        console.log("-------- EJECUTANDO REBASE --------");
        console.log("Timestamp actual:", block.timestamp);
        console.log("Ultimo rebase:", lastRebaseTime);
        console.log("Intervalo minimo:", rebaseInterval);
        
        // Obtener la tasa VCOP/COP del oráculo
        uint256 vcopToCopRate = oracle.getVcopToCopRate();
        console.log("Tasa VCOP/COP del oraculo:", vcopToCopRate);
        
        uint256 newSupply = vcop.rebase(vcopToCopRate);
        console.log("Nuevo suministro despues del rebase:", newSupply);
        
        lastRebaseTime = block.timestamp;
        console.log("Timestamp de ultimo rebase actualizado a:", lastRebaseTime);
        
        emit RebaseExecuted(vcopToCopRate, newSupply);
        console.log("-------- REBASE COMPLETADO --------");
        
        return newSupply;
    }
    
    /**
     * @dev Verifica si el pool incluye el token VCOP
     */
    function _isVCOPPool(PoolKey calldata key) internal view returns (bool) {
        bool isVCOPInPool = key.currency0 == vcopCurrency || key.currency1 == vcopCurrency;
        if (isVCOPInPool) {
            console.log("Pool VCOP identificado");
            console.log("VCOP es token0:", key.currency0 == vcopCurrency);
        }
        return isVCOPInPool;
    }
    
    /**
     * @dev Hook que se ejecuta después de un swap
     * Si el pool incluye VCOP y ha pasado suficiente tiempo, ejecuta un rebase
     */
    function _afterSwap(
        address caller,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        console.log("======== HOOK AFTERSWAP ACTIVADO ========");
        console.log("Direccion del iniciador:", caller);
        console.log("Pool ID:", uint256(keccak256(abi.encode(key))));
        
        PoolId poolId = key.toId();
        emit SwapDetected(caller, poolId);
        
        bool isVCOPPool = _isVCOPPool(key);
        bool timeElapsed = block.timestamp >= lastRebaseTime + rebaseInterval;
        
        console.log("Es pool VCOP?:", isVCOPPool);
        console.log("Tiempo suficiente para rebase?:", timeElapsed);
        
        emit VCOPPoolIdentified(poolId, key.currency0 == vcopCurrency);
        emit RebaseEvaluated(block.timestamp, lastRebaseTime, rebaseInterval, isVCOPPool && timeElapsed);
        
        if (isVCOPPool && timeElapsed) {
            // Ejecutar rebase si es necesario
            console.log("Condiciones para rebase cumplidas, ejecutando rebase...");
            executeRebase();
        } else {
            console.log("No se cumplen condiciones para rebase, ignorando");
        }
        
        console.log("======== HOOK AFTERSWAP COMPLETADO ========");
        
        return (BaseHook.afterSwap.selector, 0);
    }
} 