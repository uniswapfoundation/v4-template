// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

import "../hooks/StablecoinHookFactory.sol";
import "../hooks/StablecoinHook.sol";
import "../hooks/StablecoinHookRouter.sol";
import "../interfaces/IOracle.sol";
import "../mocks/MockOracle.sol";
import "../AlgorithmicStablecoin.sol";

contract DeployStablecoinHook is Script {
    // Uniswap v4 PoolManager address on Base Sepolia
    address constant POOL_MANAGER_ADDRESS = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
    
    // Token addresses
    address constant VCOP_ADDRESS = 0x08544C4729aD52612b9A9fC20667afD3A81dB0ce;
    address constant USDC_ADDRESS = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    
    // Oracle address
    address constant ORACLE_ADDRESS = 0x7F00d50b93886A1B4c32645cDD906169B2B85d9B;
    
    // Uniswap pool parameters
    uint24 constant POOL_FEE = 3000; // 0.3%
    int24 constant TICK_SPACING = 60;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Get instances of existing contracts
        IPoolManager poolManager = IPoolManager(POOL_MANAGER_ADDRESS);
        AlgorithmicStablecoin vcop = AlgorithmicStablecoin(VCOP_ADDRESS);
        IOracle oracle = IOracle(ORACLE_ADDRESS);
        
        // Deploy the hook factory
        StablecoinHookFactory factory = new StablecoinHookFactory(poolManager, oracle);
        
        // Deploy the hook through the factory
        factory.deployHook();
        StablecoinHook hook = factory.hook();
        
        // Deploy the router for user interactions
        StablecoinHookRouter router = new StablecoinHookRouter(poolManager, hook);
        
        // Create the pool with the hook
        // Determine token ordering for Uniswap v4 (tokens must be sorted)
        address token0 = VCOP_ADDRESS < USDC_ADDRESS ? VCOP_ADDRESS : USDC_ADDRESS;
        address token1 = VCOP_ADDRESS < USDC_ADDRESS ? USDC_ADDRESS : VCOP_ADDRESS;
        
        // Note whether the stablecoin (VCOP) is token0
        bool stablecoinIsToken0 = VCOP_ADDRESS < USDC_ADDRESS;
        
        // Initial sqrt price (this sets the initial exchange rate)
        // For 1 VCOP = 0.001 USDC (assuming 1 COP ≈ 0.00025 USD)
        // The formula is sqrt(price) * 2^96 where price is token1/token0
        // If VCOP is token0, price = USDC/VCOP
        // If VCOP is token1, price = VCOP/USDC
        uint160 sqrtPriceX96;
        
        if (stablecoinIsToken0) {
            // Price is USDC/VCOP = 0.001
            sqrtPriceX96 = 79232123187405;  // sqrt(0.001) * 2^96
        } else {
            // Price is VCOP/USDC = 1000
            sqrtPriceX96 = 2505414483750479311;  // sqrt(1000) * 2^96
        }
        
        // Create the pool through the factory
        factory.createPool(
            token0,
            token1,
            POOL_FEE,
            TICK_SPACING,
            sqrtPriceX96,
            stablecoinIsToken0
        );
        
        // Output deployment information
        console.log("Deployment completed:");
        console.log("StablecoinHookFactory:", address(factory));
        console.log("StablecoinHook:", address(hook));
        console.log("StablecoinHookRouter:", address(router));
        
        vm.stopBroadcast();
    }
} 