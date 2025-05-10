// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

import {VCOPRebased} from "src/VCOPRebased.sol";
import {VCOPOracle} from "src/VCOPOracle.sol";

/**
 * @title VCOPRebaseHook
 * @notice Hook de Uniswap v4 que monitorea el precio de VCOP y ejecuta rebases automáticos
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
    event RebaseExecuted(uint256 price, uint256 newTotalSupply);
    
    // Evento emitido cuando se actualiza el intervalo de rebase
    event RebaseIntervalUpdated(uint256 oldInterval, uint256 newInterval);

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
        
        emit RebaseIntervalUpdated(oldInterval, newInterval);
    }
    
    /**
     * @dev Ejecuta un rebase basado en el precio del oráculo
     * @return El nuevo suministro total
     */
    function executeRebase() public returns (uint256) {
        require(block.timestamp >= lastRebaseTime + rebaseInterval, "Rebase too soon");
        
        uint256 price = oracle.getPrice();
        uint256 newSupply = vcop.rebase(price);
        
        lastRebaseTime = block.timestamp;
        
        emit RebaseExecuted(price, newSupply);
        
        return newSupply;
    }
    
    /**
     * @dev Verifica si el pool incluye el token VCOP
     */
    function _isVCOPPool(PoolKey calldata key) internal view returns (bool) {
        return key.currency0 == vcopCurrency || key.currency1 == vcopCurrency;
    }
    
    /**
     * @dev Hook que se ejecuta después de un swap
     * Si el pool incluye VCOP y ha pasado suficiente tiempo, ejecuta un rebase
     */
    function _afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        if (_isVCOPPool(key) && block.timestamp >= lastRebaseTime + rebaseInterval) {
            // Ejecutar rebase si es necesario
            executeRebase();
        }
        
        return (BaseHook.afterSwap.selector, 0);
    }
} 