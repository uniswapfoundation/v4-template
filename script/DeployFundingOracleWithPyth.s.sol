// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {FundingOracle} from "../src/FundingOracle.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

/// @title Deploy FundingOracle with Pyth Integration
/// @notice Deploys FundingOracle with proper Pyth Network configuration
contract DeployFundingOracleWithPyth is Script {
    using PoolIdLibrary for PoolId;

    // Pyth contract addresses by network
    mapping(uint256 => address) pythContracts;
    
    // Well-known Pyth price feed IDs
    bytes32 public constant ETH_USD_FEED_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    bytes32 public constant BTC_USD_FEED_ID = 0xe62df6c8b4c85fe1e8961f0b4b92b4d0e7b9b3ad9b7bff0ff7f7bc2f6e5b8b9c;
    bytes32 public constant USDC_USD_FEED_ID = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;
    bytes32 public constant USDT_USD_FEED_ID = 0x2b89b9dc8fdf9f34709a5b106b472f0f39bb6ca4ce2e7a3cd5d44c6c4e8b9c33;
    
    FundingOracle public fundingOracle;
    
    function run() external {
        uint256 chainId = block.chainid;
        console.log("Deploying FundingOracle with Pyth on chain:", chainId);
        
        _initializePythAddresses();
        
        address pythContract = pythContracts[chainId];
        require(pythContract != address(0), "Pyth contract not configured for this chain");
        
        console.log("Using Pyth contract at:", pythContract);
        
        vm.startBroadcast();
        
        // Deploy FundingOracle
        fundingOracle = new FundingOracle(pythContract);
        console.log("FundingOracle deployed to:", address(fundingOracle));
        
        // Configure common markets
        _setupCommonMarkets();
        
        // Configure Pyth price sources
        _setupPythPriceSources();
        
        vm.stopBroadcast();
        
        _printDeploymentSummary();
    }
    
    function _initializePythAddresses() internal {
        // Ethereum Mainnet
        pythContracts[1] = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6;
        
        // Ethereum Sepolia
        pythContracts[11155111] = 0xDd24F84d36BF92C65F92307595335bdFab5Bbd21;
        
        // Arbitrum One
        pythContracts[42161] = 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C;
        
        // Arbitrum Sepolia
        pythContracts[421614] = 0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF;
        
        // Polygon
        pythContracts[137] = 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C;
        
        // Base
        pythContracts[8453] = 0x8250f4aF4B972684F7b336503E2D6dFeDeB1487a;
        
        // Optimism
        pythContracts[10] = 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C;
        
        // BSC
        pythContracts[56] = 0x4D7E825F80Bdf85b913e37F943Afb4243B1e175d;
        
        // Avalanche
        pythContracts[43114] = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6;
        
        // For local testing (Anvil default chain ID)
        pythContracts[31337] = address(0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF); // Placeholder
    }
    
    function _setupCommonMarkets() internal {
        console.log("\nSetting up common markets...");
        
        // Mock vAMM hook address (would be real PerpsHook in production)
        address mockVammHook = address(0x1234567890123456789012345678901234567890);
        
        // ETH-USDC Market
        PoolId ethUsdcPool = PoolId.wrap(keccak256("ETH-USDC-3000"));
        fundingOracle.addMarket(ethUsdcPool, mockVammHook, ETH_USD_FEED_ID);
        console.log("ETH-USDC market added with feed ID:", vm.toString(ETH_USD_FEED_ID));
        
        // BTC-USDC Market
        PoolId btcUsdcPool = PoolId.wrap(keccak256("BTC-USDC-3000"));
        fundingOracle.addMarket(btcUsdcPool, mockVammHook, BTC_USD_FEED_ID);
        console.log("BTC-USDC market added with feed ID:", vm.toString(BTC_USD_FEED_ID));
        
        console.log("Common markets configured successfully");
    }
    
    function _setupPythPriceSources() internal {
        console.log("\nSetting up Pyth price sources...");
        
        PoolId ethUsdcPool = PoolId.wrap(keccak256("ETH-USDC-3000"));
        PoolId btcUsdcPool = PoolId.wrap(keccak256("BTC-USDC-3000"));
        
        // Add Pyth as primary price source for ETH market
        fundingOracle.addPythPriceSource(
            ethUsdcPool,
            ETH_USD_FEED_ID,
            3, // Higher weight
            60 // 1 minute staleness
        );
        console.log("ETH Pyth price source added");
        
        // Add Pyth as primary price source for BTC market
        fundingOracle.addPythPriceSource(
            btcUsdcPool,
            BTC_USD_FEED_ID,
            3, // Higher weight
            60 // 1 minute staleness
        );
        console.log("BTC Pyth price source added");
        
        // Configure staleness threshold
        fundingOracle.setPythMaxStaleness(60); // 1 minute
        console.log("Pyth max staleness set to 60 seconds");
        
        console.log("Pyth price sources configured successfully");
    }
    
    function _printDeploymentSummary() internal view {
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Chain ID:", block.chainid);
        console.log("FundingOracle:", address(fundingOracle));
        console.log("Pyth Contract:", address(fundingOracle.pyth()));
        console.log("Max Staleness:", fundingOracle.pythMaxStaleness(), "seconds");
        
        console.log("\n=== CONFIGURED MARKETS ===");
        
        PoolId ethUsdcPool = PoolId.wrap(keccak256("ETH-USDC-3000"));
        PoolId btcUsdcPool = PoolId.wrap(keccak256("BTC-USDC-3000"));
        
        console.log("ETH-USDC Pool ID:", vm.toString(PoolId.unwrap(ethUsdcPool)));
        console.log("  Pyth Feed ID:", vm.toString(fundingOracle.pythPriceFeedIds(ethUsdcPool)));
        console.log("  Pyth Integration:", fundingOracle.hasMarketPythIntegration(ethUsdcPool));
        
        console.log("BTC-USDC Pool ID:", vm.toString(PoolId.unwrap(btcUsdcPool)));
        console.log("  Pyth Feed ID:", vm.toString(fundingOracle.pythPriceFeedIds(btcUsdcPool)));
        console.log("  Pyth Integration:", fundingOracle.hasMarketPythIntegration(btcUsdcPool));
        
        console.log("\n=== NEXT STEPS ===");
        console.log("1. Fund the contract with ETH for Pyth update fees");
        console.log("2. Add additional price sources (Chainlink, etc.) if desired");
        console.log("3. Configure PerpsHook to use this FundingOracle");
        console.log("4. Test price updates with real Pyth data");
        console.log("5. Monitor funding rate calculations");
        
        console.log("\n=== USAGE EXAMPLES ===");
        console.log("// Get ETH price from Pyth");
        console.log("(uint256 price, uint256 time) = fundingOracle.getPythPrice(ETH_USD_FEED_ID);");
        console.log("");
        console.log("// Update funding with Pyth price data");
        console.log("bytes[] memory priceData = /* fetch from Pyth API */;");
        console.log("uint256 fee = fundingOracle.getPythUpdateFee(priceData);");
        console.log("fundingOracle.updateFundingWithPyth{value: fee}(poolId, priceData);");
        
        console.log("\n=== Deployment Complete ===");
    }
}
