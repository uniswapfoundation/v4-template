// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {FundingOracle} from "../src/FundingOracle.sol";
import {MockPyth} from "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

/// @title Test Pyth Integration with FundingOracle
/// @notice Demonstrates and tests Pyth Network integration
contract TestPythIntegration is Script {
    using PoolIdLibrary for PoolId;

    FundingOracle public fundingOracle;
    MockPyth public mockPyth;
    
        // Pyth price feed IDs for testing
    bytes32 public constant MAIN_FEED_ID = 0x736999a0e4eb5f0971f3284ae492df38662f96f28c957f1417ec42f211a7f7eb; // User provided feed ID
    bytes32 public constant ETH_USD_FEED_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    bytes32 public constant BTC_USD_FEED_ID = 0xe62df6c8b4c85fe1e8961f0b4b92b4d0e7b9b3ad9b7bff0ff7f7bc2f6e5b8b9c;
    bytes32 public constant USDC_USD_FEED_ID = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;
    
    PoolId public ethUsdcPool;
    PoolId public btcUsdcPool;
    
    /// @notice Helper function to set Pyth price data using the official MockPyth interface
    function setPythPrice(bytes32 feedId, int64 price, int32 expo, uint64 conf, uint64 publishTime) internal {
        bytes memory updateData = mockPyth.createPriceFeedUpdateData(
            feedId,
            price,
            conf,
            expo,
            price, // emaPrice same as price for simplicity
            conf,  // emaConf same as conf
            publishTime,
            publishTime - 1 // prevPublishTime
        );
        
        bytes[] memory updateDataArray = new bytes[](1);
        updateDataArray[0] = updateData;
        
        bytes32[] memory priceIds = new bytes32[](1);
        priceIds[0] = feedId;
        
        mockPyth.updatePriceFeeds{value: 1}(updateDataArray);
    }
    
    function run() external {
        console.log("=== Pyth Integration Test ===");
        
        vm.startBroadcast();
        
        _deployContracts();
        _setupMarkets();
        _testPythPriceFeeds();
        _testFundingWithPyth();
        _demonstrateAdvancedFeatures();
        
        vm.stopBroadcast();
        
        console.log("=== Pyth Integration Test Complete ===");
    }
    
    function _deployContracts() internal {
        console.log("\n1. Deploying contracts...");
        
        // Deploy MockPyth (validTimePeriod: 60 seconds, updateFee: 1 wei)
        mockPyth = new MockPyth(60, 1);
        console.log("MockPyth deployed to:", address(mockPyth));
        
        // Deploy FundingOracle with Pyth
        fundingOracle = new FundingOracle(address(mockPyth));
        console.log("FundingOracle deployed to:", address(fundingOracle));
        console.log("Pyth contract configured:", address(fundingOracle.pyth()));
    }
    
    function _setupMarkets() internal {
        console.log("\n2. Setting up markets...");
        
        // Create pool IDs
        ethUsdcPool = PoolId.wrap(keccak256("ETH-USDC-3000"));
        btcUsdcPool = PoolId.wrap(keccak256("BTC-USDC-3000"));
        
        address mockVammHook = address(0x1234567890123456789012345678901234567890);
        
        // Add ETH-USDC market
        fundingOracle.addMarket(ethUsdcPool, mockVammHook, ETH_USD_FEED_ID);
        console.log("ETH-USDC market added with Pyth feed:", vm.toString(ETH_USD_FEED_ID));
        
        // Add BTC-USDC market
        fundingOracle.addMarket(btcUsdcPool, mockVammHook, BTC_USD_FEED_ID);
        console.log("BTC-USDC market added with Pyth feed:", vm.toString(BTC_USD_FEED_ID));
        
        // Verify integrations
        assertTrue(fundingOracle.hasMarketPythIntegration(ethUsdcPool));
        assertTrue(fundingOracle.hasMarketPythIntegration(btcUsdcPool));
        console.log("Markets configured with Pyth integration successfully");
    }
    
    function _testPythPriceFeeds() internal {
        console.log("\n3. Testing Pyth price feeds...");
        
        // Set ETH price
        int64 ethPrice = 1850 * 1e8; // $1850 with 8 decimals
        setPythPrice(ETH_USD_FEED_ID, ethPrice, -8, 1e6, uint64(block.timestamp));
        
        // Set BTC price
        int64 btcPrice = 43000 * 1e8; // $43,000 with 8 decimals
        setPythPrice(BTC_USD_FEED_ID, btcPrice, -8, 10e6, uint64(block.timestamp));
        
        // Test ETH price retrieval
        (uint256 ethPriceConverted, uint256 ethPublishTime) = fundingOracle.getPythPrice(ETH_USD_FEED_ID);
        console.log("ETH/USD price from Pyth:", ethPriceConverted / 1e18, "USD");
        console.log("ETH price published at:", ethPublishTime);
        
        // Test BTC price retrieval
        (uint256 btcPriceConverted, uint256 btcPublishTime) = fundingOracle.getPythPrice(BTC_USD_FEED_ID);
        console.log("BTC/USD price from Pyth:", btcPriceConverted / 1e18, "USD");
        console.log("BTC price published at:", btcPublishTime);
        
        // Test market-specific price retrieval
        (uint256 ethMarketPrice, uint256 ethMarketTime) = fundingOracle.getMarketPythPrice(ethUsdcPool);
        console.log("ETH market price:", ethMarketPrice / 1e18, "USD");
        
        // Verify prices match
        require(ethPriceConverted == ethMarketPrice, "ETH prices should match");
        require(ethPublishTime == ethMarketTime, "ETH timestamps should match");
        
        console.log("Pyth price feeds working correctly");
    }
    
    function _testFundingWithPyth() internal {
        console.log("\n4. Testing funding updates with Pyth...");
        
        // Create valid price update data for testing
        bytes memory validUpdateData = mockPyth.createPriceFeedUpdateData(
            ETH_USD_FEED_ID,
            1875 * 1e8, // Slightly different price for update
            1e6,
            -8,
            1875 * 1e8,
            1e6,
            uint64(block.timestamp),
            uint64(block.timestamp - 1)
        );
        
        bytes[] memory priceUpdateData = new bytes[](1);
        priceUpdateData[0] = validUpdateData;
        
        uint256 updateFee = fundingOracle.getPythUpdateFee(priceUpdateData);
        console.log("Pyth update fee:", updateFee, "wei");
        
        // Test price update
        console.log("Updating Pyth prices...");
        fundingOracle.updatePythPrices{value: updateFee}(priceUpdateData);
        console.log("Pyth prices updated successfully");
        
        // Test funding update with Pyth integration
        console.log("Testing funding update with Pyth data...");
        
        // Move time forward to allow funding update
        vm.warp(block.timestamp + 1 hours + 1);
        
        // Update with new price data
        fundingOracle.updateFundingWithPyth{value: updateFee}(ethUsdcPool, priceUpdateData);
        
        FundingOracle.MarketData memory marketData = fundingOracle.getMarketData(ethUsdcPool);
        console.log("Funding updated at timestamp:", marketData.lastFundingUpdate);
        console.log("Global funding index:", uint256(marketData.globalFundingIndex >= 0 ? marketData.globalFundingIndex : -marketData.globalFundingIndex));
        
        console.log("Funding updates with Pyth working correctly");
    }
    
    function _demonstrateAdvancedFeatures() internal {
        console.log("\n5. Demonstrating advanced Pyth features...");
        
        // Test adding Pyth price sources
        console.log("Adding Pyth as additional price source...");
        fundingOracle.addPythPriceSource(ethUsdcPool, ETH_USD_FEED_ID, 2, 60); // Higher weight, 1 min staleness
        
        // Test batch price setting
        console.log("Setting batch prices...");
        bytes32[] memory feedIds = new bytes32[](2);
        int64[] memory prices = new int64[](2);
        int32[] memory exponents = new int32[](2);
        
        feedIds[0] = ETH_USD_FEED_ID;
        feedIds[1] = BTC_USD_FEED_ID;
        prices[0] = 1900 * 1e8; // New ETH price
        prices[1] = 44000 * 1e8; // New BTC price
        exponents[0] = -8;
        exponents[1] = -8;
        
        // Set prices individually using our helper function
        setPythPrice(ETH_USD_FEED_ID, prices[0], exponents[0], 1e6, uint64(block.timestamp));
        setPythPrice(BTC_USD_FEED_ID, prices[1], exponents[1], 10e6, uint64(block.timestamp));
        
        // Verify new prices
        (uint256 newEthPrice,) = fundingOracle.getPythPrice(ETH_USD_FEED_ID);
        (uint256 newBtcPrice,) = fundingOracle.getPythPrice(BTC_USD_FEED_ID);
        
        console.log("Updated ETH price:", newEthPrice / 1e18, "USD");
        console.log("Updated BTC price:", newBtcPrice / 1e18, "USD");
        
        // Test staleness protection
        console.log("Testing staleness protection...");
        vm.warp(block.timestamp + 70); // Advance past staleness threshold
        
        try fundingOracle.getPythPrice(ETH_USD_FEED_ID) {
            console.log("ERROR: Should have reverted due to stale price");
        } catch {
            console.log("Staleness protection working correctly");
        }
        
        // Test price source management
        console.log("Testing price source management...");
        FundingOracle.PriceSource[] memory sources = fundingOracle.getMarketPriceSources(ethUsdcPool);
        console.log("Total price sources for ETH market:", sources.length);
        
        uint256 pythSources = 0;
        for (uint256 i = 0; i < sources.length; i++) {
            if (sources[i].isPythSource) {
                pythSources++;
                console.log("Pyth source found with feed ID:", vm.toString(sources[i].pythPriceFeedId));
            }
        }
        console.log("Pyth sources configured:", pythSources);
        
        // Test admin functions
        console.log("Testing admin functions...");
        fundingOracle.setPythMaxStaleness(120); // 2 minutes
        console.log("Max staleness updated to:", fundingOracle.pythMaxStaleness(), "seconds");
        
        // Test fee withdrawal (simulate accumulated fees)
        vm.deal(address(fundingOracle), 0.1 ether);
        address payable recipient = payable(address(0xFEE));
        fundingOracle.withdrawFees(recipient);
        console.log("Fees withdrawn successfully");
        
        console.log("Advanced features demonstration complete");
    }
    
    function assertTrue(bool condition) internal pure {
        require(condition, "Assertion failed");
    }
}
