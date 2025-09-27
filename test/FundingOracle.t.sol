// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {FundingOracle, IPriceOracle, IVAMMHook} from "../src/FundingOracle.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {MockPyth} from "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

// Mock contracts for testing
contract MockPriceOracle is IPriceOracle {
    uint256 public price;
    uint256 public updatedAt;
    
    constructor(uint256 _price) {
        price = _price;
        updatedAt = block.timestamp;
    }
    
    function setPrice(uint256 _price) external {
        price = _price;
        updatedAt = block.timestamp;
    }
    
    function getPrice(address) external view returns (uint256, uint256) {
        return (price, updatedAt); // Return actual update timestamp
    }
    
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, int256(price), block.timestamp, updatedAt, 1);
    }
}

contract MockVAMMHook is IVAMMHook {
    uint256 public markPrice;
    
    constructor(uint256 _markPrice) {
        markPrice = _markPrice;
    }
    
    function setMarkPrice(uint256 _markPrice) external {
        markPrice = _markPrice;
    }
    
    function getMarkPrice(PoolId) external view returns (uint256) {
        return markPrice;
    }
    
    function getMarketState(PoolId) external view returns (
        uint256, uint256, uint256, int256, uint256, uint256, uint256, uint256, address, bool
    ) {
        return (1000e18, 1500000e18, 1500000000e36, 0, 0, 0, 10000000e6, block.timestamp, address(0), true);
    }
}

contract FundingOracleTest is Test {
    using PoolIdLibrary for PoolId;
    
    FundingOracle public fundingOracle;
    MockPyth public mockPyth;
    MockPriceOracle public oracle1;
    MockPriceOracle public oracle2;
    MockVAMMHook public vammHook;
    
    address public owner = makeAddr("owner");
    address public keeper = makeAddr("keeper");
    
    PoolId public poolId;
    bytes32 public poolIdBytes;
    
    // Pyth price feed IDs for testing
    bytes32 public constant MAIN_FEED_ID = 0x736999a0e4eb5f0971f3284ae492df38662f96f28c957f1417ec42f211a7f7eb; // Your provided feed ID
    bytes32 public constant ETH_USD_FEED_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    bytes32 public constant BTC_USD_FEED_ID = 0xe62df6c8b4c85fe1e8961f0b4b92b4d0e7b9b3ad9b7bff0ff7f7bc2f6e5b8b9c;
    
    uint256 constant INITIAL_PRICE = 1500e18; // $1500 ETH
    uint256 constant PRICE_PRECISION = 1e18;
    uint256 constant FUNDING_PRECISION = 1e18;

    event MarketAdded(PoolId indexed poolId, address vammHook);
    event FundingUpdated(PoolId indexed poolId, int256 newFundingIndex, int256 fundingRate, uint256 timestamp);
    event PriceSourceAdded(PoolId indexed poolId, address oracle, uint256 weight);
    event MarkPriceUpdated(PoolId indexed poolId, uint256 markPrice, uint256 spotPrice, int256 premium);
    event MarketStatusChanged(PoolId indexed poolId, bool isActive);

    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy MockPyth first (validTimePeriod: 60 seconds, updateFee: 1 wei)
        mockPyth = new MockPyth(60, 1);
        
        // Deploy FundingOracle with MockPyth address
        fundingOracle = new FundingOracle(address(mockPyth));
        
        // Deploy other mock contracts
        oracle1 = new MockPriceOracle(INITIAL_PRICE);
        oracle2 = new MockPriceOracle(INITIAL_PRICE);
        vammHook = new MockVAMMHook(INITIAL_PRICE);
        
        // Create a mock pool ID
        poolIdBytes = keccak256("ETH-USDC-3000");
        poolId = PoolId.wrap(poolIdBytes);
        
        // Add market with your provided Pyth feed ID
        fundingOracle.addMarket(poolId, address(vammHook), MAIN_FEED_ID);
        
        // Add traditional price sources
        fundingOracle.addPriceSource(poolId, address(oracle1), 1, 300); // 5 min max age
        fundingOracle.addPriceSource(poolId, address(oracle2), 1, 300);
        
        // Add Pyth price source using your feed ID
        fundingOracle.addPythPriceSource(poolId, MAIN_FEED_ID, 1, 60); // 1 min max age
        
        vm.stopPrank();
    }

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

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_deployment() public {
        assertEq(fundingOracle.owner(), owner);
        assertEq(address(fundingOracle.pyth()), address(mockPyth));
        assertEq(fundingOracle.DEFAULT_FUNDING_INTERVAL(), 1 hours);
        assertEq(fundingOracle.DEFAULT_MAX_FUNDING_RATE(), 0.01e18); // 1%
        assertEq(fundingOracle.DEFAULT_FUNDING_RATE_FACTOR(), 0.5e18); // 0.5
        assertEq(fundingOracle.PRICE_PRECISION(), 1e18);
        assertEq(fundingOracle.FUNDING_PRECISION(), 1e18);
        assertEq(fundingOracle.pythMaxStaleness(), 60);
    }

    /*//////////////////////////////////////////////////////////////
                            MARKET MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_addMarket_success() public {
        PoolId newPoolId = PoolId.wrap(keccak256("BTC-USDC-3000"));
        address newVammHook = makeAddr("newVammHook");
        
        vm.startPrank(owner);
        
        vm.expectEmit(true, false, false, true);
        emit MarketAdded(newPoolId, newVammHook);
        
        fundingOracle.addMarket(newPoolId, newVammHook, BTC_USD_FEED_ID);
        
        // Check market data
        FundingOracle.MarketData memory marketData = fundingOracle.getMarketData(newPoolId);
        assertEq(marketData.globalFundingIndex, 0);
        assertEq(marketData.lastFundingUpdate, block.timestamp);
        assertEq(marketData.fundingInterval, fundingOracle.DEFAULT_FUNDING_INTERVAL());
        assertEq(marketData.maxFundingRate, fundingOracle.DEFAULT_MAX_FUNDING_RATE());
        assertEq(marketData.fundingRateFactor, fundingOracle.DEFAULT_FUNDING_RATE_FACTOR());
        assertTrue(marketData.isActive);
        
        // Check Pyth integration
        assertEq(fundingOracle.pythPriceFeedIds(newPoolId), BTC_USD_FEED_ID);
        assertTrue(fundingOracle.hasMarketPythIntegration(newPoolId));
        
        vm.stopPrank();
    }

    function test_addMarket_revert_invalid_hook() public {
        PoolId newPoolId = PoolId.wrap(keccak256("BTC-USDC-3000"));
        
        vm.startPrank(owner);
        
        vm.expectRevert("Invalid vAMM hook");
        fundingOracle.addMarket(newPoolId, address(0), bytes32(0));
        
        vm.stopPrank();
    }

    function test_addPriceSource_success() public {
        address newOracle = makeAddr("newOracle");
        uint256 weight = 2;
        uint256 maxAge = 600;
        
        vm.startPrank(owner);
        
        vm.expectEmit(true, false, false, true);
        emit PriceSourceAdded(poolId, newOracle, weight);
        
        fundingOracle.addPriceSource(poolId, newOracle, weight, maxAge);
        
        vm.stopPrank();
    }

    function test_addPriceSource_revert_market_not_found() public {
        PoolId nonExistentPool = PoolId.wrap(keccak256("NONEXISTENT"));
        
        vm.startPrank(owner);
        
        vm.expectRevert(FundingOracle.MarketNotFound.selector);
        fundingOracle.addPriceSource(nonExistentPool, address(oracle1), 1, 300);
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            PRICE CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getMarkPrice_single_source() public {
        // When vAMM and oracles have different prices, median is calculated
        vammHook.setMarkPrice(1600e18);  // vAMM: $1600
        // Oracle1 and Oracle2 are still at initial price: $1500 each from setUp
        
        uint256 markPrice = fundingOracle.getMarkPrice(poolId);
        // Median of [1500, 1500, 1600] = 1500
        assertEq(markPrice, 1500e18);
    }

    function test_getMarkPrice_multiple_sources() public {
        // Set different prices for median calculation
        vammHook.setMarkPrice(1500e18);  // vAMM: $1500
        oracle1.setPrice(1510e18);       // Oracle1: $1510
        oracle2.setPrice(1490e18);       // Oracle2: $1490
        
        uint256 markPrice = fundingOracle.getMarkPrice(poolId);
        
        // Median of [1490, 1500, 1510] = 1500
        assertEq(markPrice, 1500e18);
    }

    function test_getMarkPrice_with_stale_oracle() public {
        // Set oracle1 to stale price
        vm.warp(block.timestamp + 400); // 400 seconds later (> 300 max age)
        
        oracle2.setPrice(1520e18); // Fresh price
        vammHook.setMarkPrice(1505e18);
        
        uint256 markPrice = fundingOracle.getMarkPrice(poolId);
        
        // Should only use vAMM (1505) and oracle2 (1520), median = average of 2 = 1512.5
        assertEq(markPrice, 1512.5e18);
    }

    function test_getSpotPrice_success() public {
        oracle1.setPrice(1495e18);
        oracle2.setPrice(1505e18);
        
        uint256 spotPrice = fundingOracle.getSpotPrice(poolId);
        
        // Median of [1495, 1505] = average = 1500
        assertEq(spotPrice, 1500e18);
    }

    function test_getSpotPrice_fallback_to_vamm() public {
        // Create market without external oracles
        PoolId newPoolId = PoolId.wrap(keccak256("TEST-USDC"));
        MockVAMMHook newVammHook = new MockVAMMHook(1800e18);
        
        vm.startPrank(owner);
        fundingOracle.addMarket(newPoolId, address(newVammHook), bytes32(0));
        vm.stopPrank();
        
        uint256 spotPrice = fundingOracle.getSpotPrice(newPoolId);
        
        // Should fallback to vAMM mark price
        assertEq(spotPrice, 1800e18);
    }

    /*//////////////////////////////////////////////////////////////
                            PYTH INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_pythPriceIntegration() public {
        // Set Pyth price using your feed ID
        setPythPrice(MAIN_FEED_ID, 1550 * 1e8, -8, 1e6, uint64(block.timestamp));
        
        // Get Pyth price through oracle
        (uint256 price, uint256 publishTime) = fundingOracle.getPythPrice(MAIN_FEED_ID);
        
        assertEq(price, 1550e18); // Should be converted to 1e18 precision
        assertEq(publishTime, block.timestamp);
    }

    function test_marketPythPrice() public {
        // Set Pyth price for the main market using your feed ID
        setPythPrice(MAIN_FEED_ID, 1600 * 1e8, -8, 1e6, uint64(block.timestamp));
        
        (uint256 price, uint256 publishTime) = fundingOracle.getMarketPythPrice(poolId);
        
        assertEq(price, 1600e18);
        assertEq(publishTime, block.timestamp);
    }

    function test_updatePythPrices() public {
        // Create valid price update data
        bytes memory updateData = mockPyth.createPriceFeedUpdateData(
            MAIN_FEED_ID,
            1550 * 1e8,
            1e6,
            -8,
            1550 * 1e8,
            1e6,
            uint64(block.timestamp),
            uint64(block.timestamp - 1)
        );
        
        bytes[] memory priceUpdateData = new bytes[](1);
        priceUpdateData[0] = updateData;
        
        uint256 fee = mockPyth.getUpdateFee(priceUpdateData);
        
        // Should succeed with sufficient fee
        fundingOracle.updatePythPrices{value: fee}(priceUpdateData);
        
        // Should revert with insufficient fee
        vm.expectRevert(FundingOracle.InsufficientPythFee.selector);
        fundingOracle.updatePythPrices{value: fee - 1}(priceUpdateData);
    }

    function test_getPythUpdateFee() public {
        bytes[] memory priceUpdateData = new bytes[](1);
        priceUpdateData[0] = hex"deadbeef";
        
        uint256 fee = fundingOracle.getPythUpdateFee(priceUpdateData);
        uint256 mockFee = mockPyth.getUpdateFee(priceUpdateData);
        
        assertEq(fee, mockFee);
    }

    function test_updateFundingWithPyth() public {
        // Set up price scenario using your feed ID
        setPythPrice(MAIN_FEED_ID, 1520 * 1e8, -8, 1e6, uint64(block.timestamp));
        oracle1.setPrice(1500e18);
        oracle2.setPrice(1510e18);
        vammHook.setMarkPrice(1530e18);
        
        // Move forward in time
        vm.warp(block.timestamp + 1 hours + 1);
        
        // Create valid price update data for the new time
        bytes memory updateData = mockPyth.createPriceFeedUpdateData(
            MAIN_FEED_ID,
            1525 * 1e8, // Slightly different price
            1e6,
            -8,
            1525 * 1e8, // emaPrice
            1e6,        // emaConf
            uint64(block.timestamp),
            uint64(block.timestamp - 1)
        );
        
        bytes[] memory priceUpdateData = new bytes[](1);
        priceUpdateData[0] = updateData;
        uint256 fee = mockPyth.getUpdateFee(priceUpdateData);
        
        // Update funding with Pyth data
        fundingOracle.updateFundingWithPyth{value: fee}(poolId, priceUpdateData);
        
        FundingOracle.MarketData memory marketData = fundingOracle.getMarketData(poolId);
        assertTrue(marketData.globalFundingIndex != 0);
    }

    function test_updateFundingWithPyth_no_price_data() public {
        // Test updating without price data (empty array)
        vm.warp(block.timestamp + 1 hours + 1);
        
        // Set fresh oracle prices after warp
        oracle1.setPrice(1500e18);
        oracle2.setPrice(1510e18);
        
        bytes[] memory emptyPriceData = new bytes[](0);
        
        // Should work without requiring payment
        fundingOracle.updateFundingWithPyth(poolId, emptyPriceData);
        
        FundingOracle.MarketData memory marketData = fundingOracle.getMarketData(poolId);
        // Should have updated funding even without Pyth data
        assertTrue(marketData.lastFundingUpdate == block.timestamp);
    }

    function test_pythPriceInMarkCalculation() public {
        // Set different prices across sources including Pyth using your feed ID
        setPythPrice(MAIN_FEED_ID, 1540 * 1e8, -8, 1e6, uint64(block.timestamp));
        oracle1.setPrice(1520e18);
        oracle2.setPrice(1530e18);
        vammHook.setMarkPrice(1510e18);
        
        uint256 markPrice = fundingOracle.getMarkPrice(poolId);
        
        // Mark price should be median of [1510, 1520, 1530, 1540] = (1520 + 1530) / 2 = 1525
        assertEq(markPrice, 1525e18);
    }

    function test_pythPriceInSpotCalculation() public {
        // Set Pyth and oracle prices for spot calculation using your feed ID
        setPythPrice(MAIN_FEED_ID, 1515 * 1e8, -8, 1e6, uint64(block.timestamp));
        oracle1.setPrice(1505e18);
        oracle2.setPrice(1525e18);
        
        uint256 spotPrice = fundingOracle.getSpotPrice(poolId);
        
        // Spot price should be median of [1505, 1515, 1525] = 1515
        assertEq(spotPrice, 1515e18);
    }

    function test_stalePythPrice() public {
        // Set Pyth price that will become stale using your feed ID
        setPythPrice(MAIN_FEED_ID, 1600 * 1e8, -8, 1e6, uint64(block.timestamp));
        
        // Move forward past staleness threshold
        vm.warp(block.timestamp + 61); // Past 60 second threshold
        
        // Should not include stale Pyth price in calculation
        uint256 markPrice = fundingOracle.getMarkPrice(poolId);
        
        // Should only use vAMM + 2 oracles, not the stale Pyth price
        // Median of [1500, 1500, 1500] = 1500 (all at initial price)
        assertEq(markPrice, 1500e18);
    }

    function test_setPythPriceFeedId() public {
        PoolId newPoolId = PoolId.wrap(keccak256("NEW-MARKET"));
        address newVammHook = makeAddr("newVammHook");
        bytes32 newFeedId = keccak256("NEW_FEED_ID");
        
        vm.startPrank(owner);
        
        // Add market first
        fundingOracle.addMarket(newPoolId, newVammHook, bytes32(0));
        
        // Set Pyth feed ID
        fundingOracle.setPythPriceFeedId(newPoolId, newFeedId);
        
        assertEq(fundingOracle.pythPriceFeedIds(newPoolId), newFeedId);
        assertTrue(fundingOracle.hasMarketPythIntegration(newPoolId));
        
        vm.stopPrank();
    }

    function test_setPythMaxStaleness() public {
        uint256 newStaleness = 120; // 2 minutes
        
        vm.startPrank(owner);
        
        fundingOracle.setPythMaxStaleness(newStaleness);
        
        assertEq(fundingOracle.pythMaxStaleness(), newStaleness);
        
        vm.stopPrank();
    }

    function test_withdrawFees() public {
        address payable recipient = payable(makeAddr("recipient"));
        
        // Send some ETH to the contract (simulating accumulated fees)
        vm.deal(address(fundingOracle), 1 ether);
        
        uint256 initialBalance = recipient.balance;
        
        vm.startPrank(owner);
        
        fundingOracle.withdrawFees(recipient);
        
        assertEq(recipient.balance, initialBalance + 1 ether);
        assertEq(address(fundingOracle).balance, 0);
        
        vm.stopPrank();
    }

    function test_getMarketPriceSources() public {
        FundingOracle.PriceSource[] memory sources = fundingOracle.getMarketPriceSources(poolId);
        
        // Should have 3 sources: 2 traditional oracles + 1 Pyth
        assertEq(sources.length, 3);
        
        // Check traditional oracles
        assertEq(sources[0].oracle, address(oracle1));
        assertFalse(sources[0].isPythSource);
        
        assertEq(sources[1].oracle, address(oracle2));
        assertFalse(sources[1].isPythSource);
        
        // Check Pyth source
        assertEq(sources[2].oracle, address(mockPyth));
        assertTrue(sources[2].isPythSource);
        assertEq(sources[2].pythPriceFeedId, MAIN_FEED_ID);
    }

    function test_premiumX18() public {
        // Create scenario where mark != spot
        vammHook.setMarkPrice(1530e18);  // vAMM: $1530
        oracle1.setPrice(1500e18);       // Oracle1: $1500  
        oracle2.setPrice(1510e18);       // Oracle2: $1510
        
        int256 premium = fundingOracle.premiumX18(poolId);
        
        // Mark price = median([1500, 1510, 1530]) = 1510
        // Spot price = median([1500, 1510]) = 1505  
        // Premium = mark - spot = 1510 - 1505 = 5
        assertEq(premium, 5e18);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _refreshOracles() internal {
        oracle1.setPrice(oracle1.price());
        oracle2.setPrice(oracle2.price());
    }

    /*//////////////////////////////////////////////////////////////
                            FUNDING CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateFunding_positive_premium() public {
        // Setup: Create scenario where mark > spot
        vammHook.setMarkPrice(1530e18);  // vAMM: $1530
        
        // Move forward past funding interval
        vm.warp(block.timestamp + 1 hours + 1);
        
        // Set fresh oracle prices after warp
        oracle1.setPrice(1500e18);       // Oracle1: $1500
        oracle2.setPrice(1510e18);       // Oracle2: $1510
        
        fundingOracle.updateFunding(poolId);
        
        FundingOracle.MarketData memory marketData = fundingOracle.getMarketData(poolId);
        
        // Mark price = median([1500, 1510, 1530]) = 1510
        // Spot price = median([1500, 1510]) = 1505
        // Premium = (1510 - 1505) / 1505 = 5/1505 ≈ 0.0033...
        // Should have positive funding (longs pay shorts)
        assertTrue(marketData.globalFundingIndex > 0);
        assertEq(marketData.markPrice, 1510e18);
        assertEq(marketData.spotPrice, 1505e18);
    }

    function test_updateFunding_negative_premium() public {
        // Setup: Create scenario where mark < spot
        vammHook.setMarkPrice(1490e18);  // vAMM: $1490
        
        vm.warp(block.timestamp + 1 hours + 1);
        
        // Set fresh oracle prices after warp
        oracle1.setPrice(1500e18);       // Oracle1: $1500
        oracle2.setPrice(1520e18);       // Oracle2: $1520
        
        fundingOracle.updateFunding(poolId);
        
        FundingOracle.MarketData memory marketData = fundingOracle.getMarketData(poolId);
        
        // Mark price = median([1490, 1500, 1520]) = 1500
        // Spot price = median([1500, 1520]) = 1510  
        // Premium = (1500 - 1510) / 1510 = -10/1510 < 0
        // Funding rate should be negative (shorts pay longs)
        assertTrue(marketData.globalFundingIndex < 0);
    }

    function test_updateFunding_max_rate_cap() public {
        // Setup: huge premium to test cap - all prices very different
        vammHook.setMarkPrice(2500e18);  // vAMM: $2500
        
        vm.warp(block.timestamp + 1 hours + 1);
        
        // Set fresh oracle prices after warp
        oracle1.setPrice(1000e18);       // Oracle1: $1000  
        oracle2.setPrice(1200e18);       // Oracle2: $1200
        
        fundingOracle.updateFunding(poolId);
        
        FundingOracle.MarketData memory marketData = fundingOracle.getMarketData(poolId);
        
        // Mark price = median([1000, 1200, 2500]) = 1200
        // Spot price = median([1000, 1200]) = 1100
        // Even with big premium, should be capped at max funding rate (1% per interval)
        uint256 maxRate = uint256(fundingOracle.DEFAULT_MAX_FUNDING_RATE());
        assertTrue(uint256(marketData.globalFundingIndex) <= maxRate);
    }

    function test_updateFunding_too_early() public {
        // Try to update before interval passes
        fundingOracle.updateFunding(poolId);
        
        FundingOracle.MarketData memory marketData = fundingOracle.getMarketData(poolId);
        
        // Should not update
        assertEq(marketData.globalFundingIndex, 0);
    }

    function test_updateFunding_revert_inactive_market() public {
        vm.startPrank(owner);
        fundingOracle.setMarketStatus(poolId, false);
        vm.stopPrank();
        
        vm.warp(block.timestamp + 1 hours + 1);
        
        vm.expectRevert(FundingOracle.MarketNotActive.selector);
        fundingOracle.updateFunding(poolId);
    }

    /*//////////////////////////////////////////////////////////////
                            CONFIGURATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setMarketStatus() public {
        vm.startPrank(owner);
        
        vm.expectEmit(true, false, false, true);
        emit MarketStatusChanged(poolId, false);
        
        fundingOracle.setMarketStatus(poolId, false);
        
        FundingOracle.MarketData memory marketData = fundingOracle.getMarketData(poolId);
        assertFalse(marketData.isActive);
        
        vm.stopPrank();
    }

    function test_updateFundingParameters() public {
        uint256 newInterval = 2 hours;
        int256 newMaxRate = 0.02e18; // 2%
        uint256 newFactor = 0.8e18; // 0.8 sensitivity
        
        vm.startPrank(owner);
        
        fundingOracle.updateFundingParameters(poolId, newInterval, newMaxRate, newFactor);
        
        FundingOracle.MarketData memory marketData = fundingOracle.getMarketData(poolId);
        assertEq(marketData.fundingInterval, newInterval);
        assertEq(marketData.maxFundingRate, newMaxRate);
        assertEq(marketData.fundingRateFactor, newFactor);
        
        vm.stopPrank();
    }

    function test_updateFundingParameters_revert_invalid() public {
        vm.startPrank(owner);
        
        vm.expectRevert(FundingOracle.InvalidFundingParameters.selector);
        fundingOracle.updateFundingParameters(poolId, 0, 0.01e18, 0.5e18); // Invalid interval
        
        vm.expectRevert(FundingOracle.InvalidFundingParameters.selector);
        fundingOracle.updateFundingParameters(poolId, 1 hours, 0, 0.5e18); // Invalid max rate
        
        vm.expectRevert(FundingOracle.InvalidFundingParameters.selector);
        fundingOracle.updateFundingParameters(poolId, 1 hours, 0.01e18, 0); // Invalid factor
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getFundingIndex() public {
        int256 index = fundingOracle.getFundingIndex(poolId);
        assertEq(index, 0);
        
        // After funding update - create distinct prices for premium
        vammHook.setMarkPrice(1520e18);       // vAMM: $1520
        
        vm.warp(block.timestamp + 1 hours + 1);
        
        // Set fresh oracle prices after warp
        oracle1.setPrice(1510e18);            // Oracle1: $1510  
        oracle2.setPrice(1500e18);            // Oracle2: $1500
        fundingOracle.updateFunding(poolId);
        
        index = fundingOracle.getFundingIndex(poolId);
        assertTrue(index > 0);
    }

    function test_needsFundingUpdate() public {
        // Initially false (just created)
        assertFalse(fundingOracle.needsFundingUpdate(poolId));
        
        // After interval passes
        vm.warp(block.timestamp + 1 hours + 1);
        assertTrue(fundingOracle.needsFundingUpdate(poolId));
        
        // Set oracle prices for update to work
        oracle1.setPrice(1500e18);
        oracle2.setPrice(1500e18);
        vammHook.setMarkPrice(1500e18);
        
        // After update, false again
        fundingOracle.updateFunding(poolId);
        assertFalse(fundingOracle.needsFundingUpdate(poolId));
    }

    /*//////////////////////////////////////////////////////////////
                            INTEGRATION SCENARIO TESTS
    //////////////////////////////////////////////////////////////*/

    function test_full_funding_cycle() public {
        // Day 1: Mark > Spot (longs pay)
        // Set prices to create distinct median values
        vammHook.setMarkPrice(1530e18);      // vAMM: $1530  
        
        vm.warp(block.timestamp + 1 hours + 1);
        
        // Set fresh oracle prices after warp
        oracle1.setPrice(1520e18);           // Oracle1: $1520
        oracle2.setPrice(1500e18);           // Oracle2: $1500
        fundingOracle.updateFunding(poolId);
        
        int256 index1 = fundingOracle.getFundingIndex(poolId);
        assertTrue(index1 > 0);
        
        // Day 2: Mark < Spot (shorts pay)
        vammHook.setMarkPrice(1480e18);
        
        vm.warp(block.timestamp + 1 hours + 1);
        
        // Set fresh oracle prices after warp to create spot > mark
        oracle1.setPrice(1510e18);  // Oracle1: $1510
        oracle2.setPrice(1520e18);  // Oracle2: $1520
        
        fundingOracle.updateFunding(poolId);
        
        int256 index2 = fundingOracle.getFundingIndex(poolId);
        assertTrue(index2 < index1); // Should decrease due to negative funding
        
        // Day 3: Prices equal (no funding)
        vammHook.setMarkPrice(1500e18);
        
        vm.warp(block.timestamp + 1 hours + 1);
        
        // Set fresh oracle prices after warp - all equal for zero premium
        oracle1.setPrice(1500e18);
        oracle2.setPrice(1500e18);
        
        fundingOracle.updateFunding(poolId);
        
        int256 index3 = fundingOracle.getFundingIndex(poolId);
        assertEq(index3, index2); // Should be same (no premium = no funding)
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_fundingRate_calculation(uint256 markPrice, uint256 spotPrice) public {
        markPrice = bound(markPrice, 500e18, 5000e18); // $500 - $5000
        spotPrice = bound(spotPrice, 500e18, 5000e18);
        
        // Skip test if prices would create zero premium after median calculation
        // vAMM price needs to be different enough to affect the median
        if (markPrice == spotPrice) {
            // When both are equal, no premium expected
            return;
        }
        
        // Set prices to ensure distinct medians
        vammHook.setMarkPrice(markPrice);
        
        vm.warp(block.timestamp + 1 hours + 1);
        
        // Create oracle prices that will result in different spot price - set after warp for freshness
        // For simplicity, set both oracles to same price to get predictable spot price
        oracle1.setPrice(spotPrice);
        oracle2.setPrice(spotPrice);
        fundingOracle.updateFunding(poolId);
        
        int256 fundingIndex = fundingOracle.getFundingIndex(poolId);
        
        // Get actual prices used for calculation
        uint256 actualMarkPrice = fundingOracle.getMarkPrice(poolId);  
        uint256 actualSpotPrice = fundingOracle.getSpotPrice(poolId);
        
        if (actualMarkPrice > actualSpotPrice) {
            assertTrue(fundingIndex > 0, "Funding should be positive when mark > spot");
        } else if (actualMarkPrice < actualSpotPrice) {
            assertTrue(fundingIndex < 0, "Funding should be negative when mark < spot");
        } else {
            assertEq(fundingIndex, 0, "Funding should be zero when mark == spot");
        }
        
        // Should never exceed max rate
        uint256 absIndex = uint256(fundingIndex >= 0 ? fundingIndex : -fundingIndex);
        assertLe(absIndex, uint256(fundingOracle.DEFAULT_MAX_FUNDING_RATE()));
    }

    function testFuzz_pythPriceConversion(int64 pythPrice, int32 expo) public {
        // Use realistic bounds for Pyth price feeds
        // Price: bound to reasonable crypto price range in base units
        pythPrice = int64(bound(int256(pythPrice), 1e6, 1e12)); // 1M to 1T base units
        // Exponent: bound to real Pyth feed range
        expo = int32(bound(int256(expo), -12, -4)); // Real feeds use -8 typically
        
        // Set price in mock Pyth
        setPythPrice(MAIN_FEED_ID, pythPrice, expo, 1e6, uint64(block.timestamp));
        
        // Get the converted price
        (uint256 convertedPrice,) = fundingOracle.getPythPrice(MAIN_FEED_ID);
        
        // Verify price is reasonable and positive
        assertTrue(convertedPrice > 0, "Converted price should be positive");
        // With our bounds, max possible price is 1e12 * 1e18 / 1e4 = 1e26
        assertTrue(convertedPrice < 1e26, "Converted price should be within bounds");
    }

    function testFuzz_fundingWithPythIntegration(uint256 pythPriceUsd, uint256 oracle1Price, uint256 oracle2Price) public {
        // Bound prices to reasonable ranges
        pythPriceUsd = bound(pythPriceUsd, 500e18, 5000e18); // $500-$5000
        oracle1Price = bound(oracle1Price, 500e18, 5000e18);
        oracle2Price = bound(oracle2Price, 500e18, 5000e18);
        
        // Set up prices
        setPythPrice(MAIN_FEED_ID, int64(int256(pythPriceUsd / 1e10)), -8, 1e6, uint64(block.timestamp));
        
        vm.warp(block.timestamp + 1 hours + 1);
        oracle1.setPrice(oracle1Price);
        oracle2.setPrice(oracle2Price);
        vammHook.setMarkPrice((pythPriceUsd + oracle1Price + oracle2Price) / 3); // Average for neutral scenario
        
        bytes[] memory emptyData = new bytes[](0);
        fundingOracle.updateFundingWithPyth(poolId, emptyData);
        
        // Should complete without reverting
        FundingOracle.MarketData memory marketData = fundingOracle.getMarketData(poolId);
        assertTrue(marketData.lastFundingUpdate == block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                            ERROR CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getMarkPrice_revert_no_vamm() public {
        PoolId invalidPool = PoolId.wrap(keccak256("INVALID"));
        
        vm.expectRevert(FundingOracle.MarketNotFound.selector);
        fundingOracle.getMarkPrice(invalidPool);
    }
}
