// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./StablecoinHook.sol";

/**
 * @title StablecoinHookRouter
 * @notice Router to help users interact with pools using the StablecoinHook
 */
contract StablecoinHookRouter {
    using PoolIdLibrary for PoolKey;
    using SafeERC20 for IERC20;

    IPoolManager public immutable poolManager;
    StablecoinHook public immutable hook;
    
    constructor(IPoolManager _poolManager, StablecoinHook _hook) {
        poolManager = _poolManager;
        hook = _hook;
    }
    
    /**
     * @notice Swap tokens in a Uniswap v4 pool with our hook
     * @param key Pool key for the swap
     * @param params Swap parameters
     * @param amountIn Amount of tokens to swap in
     * @param minAmountOut Minimum amount of tokens to receive
     * @param deadline Timestamp after which the transaction will revert
     * @return amountOut Amount of tokens received
     */
    function swap(
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 deadline
    ) external returns (uint256 amountOut) {
        require(block.timestamp <= deadline, "Transaction expired");
        
        // Determine which token to transfer in
        address tokenIn = params.zeroForOne ? address(Currency.unwrap(key.currency0)) : address(Currency.unwrap(key.currency1));
        address tokenOut = params.zeroForOne ? address(Currency.unwrap(key.currency1)) : address(Currency.unwrap(key.currency0));
        
        // Transfer tokens from the caller
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        
        // Approve the pool manager to spend tokens
        IERC20(tokenIn).approve(address(poolManager), amountIn);
        
        // Execute the swap
        BalanceDelta delta = poolManager.swap(key, params, new bytes(0));
        
        // Process the swap result
        int256 amount0Delta = delta.amount0();
        int256 amount1Delta = delta.amount1();
        
        // Calculate the amount out (negative delta means tokens flowing to the user)
        int256 amountOutDelta = params.zeroForOne ? amount1Delta : amount0Delta;
        require(amountOutDelta < 0, "Unexpected swap result");
        
        // Convert to unsigned and ensure minimum amount
        amountOut = uint256(-amountOutDelta);
        require(amountOut >= minAmountOut, "Insufficient output amount");
        
        // Transfer tokens to the caller
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
        
        return amountOut;
    }
    
    /**
     * @notice Add liquidity to a Uniswap v4 pool with our hook
     * @param key Pool key
     * @param params Liquidity parameters
     * @param amount0Desired Desired amount of token0
     * @param amount1Desired Desired amount of token1
     * @param amount0Min Minimum amount of token0
     * @param amount1Min Minimum amount of token1
     * @param deadline Timestamp after which the transaction will revert
     * @return liquidity Amount of liquidity added
     * @return amount0 Amount of token0 used
     * @return amount1 Amount of token1 used
     */
    function addLiquidity(
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        uint256 deadline
    ) external returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        require(block.timestamp <= deadline, "Transaction expired");
        
        // Get token addresses
        address token0 = address(Currency.unwrap(key.currency0));
        address token1 = address(Currency.unwrap(key.currency1));
        
        // Transfer tokens from the caller
        if (amount0Desired > 0) {
            IERC20(token0).safeTransferFrom(msg.sender, address(this), amount0Desired);
            IERC20(token0).approve(address(poolManager), amount0Desired);
        }
        
        if (amount1Desired > 0) {
            IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1Desired);
            IERC20(token1).approve(address(poolManager), amount1Desired);
        }
        
        // Add liquidity
        BalanceDelta delta = poolManager.modifyLiquidity(key, params, new bytes(0));
        
        // Process the result
        int256 amount0Delta = delta.amount0();
        int256 amount1Delta = delta.amount1();
        
        // Calculate actual amounts used (positive delta means tokens going into the pool)
        amount0 = amount0Delta > 0 ? uint256(amount0Delta) : 0;
        amount1 = amount1Delta > 0 ? uint256(amount1Delta) : 0;
        
        require(amount0 >= amount0Min, "Insufficient token0 amount");
        require(amount1 >= amount1Min, "Insufficient token1 amount");
        
        // Refund unused tokens
        if (amount0 < amount0Desired) {
            IERC20(token0).safeTransfer(msg.sender, amount0Desired - amount0);
        }
        
        if (amount1 < amount1Desired) {
            IERC20(token1).safeTransfer(msg.sender, amount1Desired - amount1);
        }
        
        // Calculate liquidity amount (this is a simplified approach)
        liquidity = params.liquidityDelta > 0 ? uint128(params.liquidityDelta) : 0;
        
        return (liquidity, amount0, amount1);
    }
} 