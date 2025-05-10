// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {StablecoinHook} from "./StablecoinHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IOracle.sol";

/**
 * @title StablecoinHookFactory
 * @notice Factory to deploy and manage stablecoin hooks for Uniswap v4 pools
 */
contract StablecoinHookFactory is Ownable {
    using PoolIdLibrary for PoolKey;

    // PoolManager reference
    IPoolManager public immutable poolManager;
    
    // Oracle reference
    IOracle public oracle;
    
    // Deployed hook reference
    StablecoinHook public hook;
    
    // Events
    event HookDeployed(address hookAddress);
    event PoolCreated(PoolId poolId, address token0, address token1, uint24 fee);
    
    constructor(IPoolManager _poolManager, IOracle _oracle) Ownable(msg.sender) {
        poolManager = _poolManager;
        oracle = _oracle;
    }
    
    /**
     * @notice Deploy the hook contract
     */
    function deployHook() external onlyOwner {
        require(address(hook) == address(0), "Hook already deployed");
        
        hook = new StablecoinHook(poolManager, oracle);
        emit HookDeployed(address(hook));
    }
    
    /**
     * @notice Create a new pool with the stablecoin hook
     * @param token0 Address of token0
     * @param token1 Address of token1
     * @param fee Pool fee
     * @param tickSpacing Tick spacing
     * @param sqrtPriceX96 Initial sqrt price
     * @param stablecoinIsToken0 Whether the stablecoin is token0
     */
    function createPool(
        address token0,
        address token1,
        uint24 fee,
        int24 tickSpacing,
        uint160 sqrtPriceX96,
        bool stablecoinIsToken0
    ) external onlyOwner returns (PoolId poolId) {
        require(address(hook) != address(0), "Hook not deployed");
        
        // Create the pool key
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(hook))
        });
        
        // Initialize the pool
        poolManager.initialize(key, sqrtPriceX96);
        
        // Authorize the pool in the hook
        hook.authorizePool(key, stablecoinIsToken0);
        
        // Get the pool ID
        poolId = key.toId();
        
        emit PoolCreated(poolId, token0, token1, fee);
        
        return poolId;
    }
    
    /**
     * @notice Update the oracle
     * @param _oracle New oracle address
     */
    function updateOracle(IOracle _oracle) external onlyOwner {
        require(address(_oracle) != address(0), "Invalid oracle address");
        oracle = _oracle;
        
        // Update oracle in hook if deployed
        if (address(hook) != address(0)) {
            hook.setOracle(_oracle);
        }
    }
} 