// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {LiquidationEngine} from "../src/LiquidationEngine.sol";
import {PositionManager} from "../src/PositionManagerV2.sol";
import {PositionFactory} from "../src/PositionFactory.sol";
import {PositionNFT} from "../src/PositionNFT.sol";
import {MarketManager} from "../src/MarketManager.sol";
import {PositionLib} from "../src/libraries/PositionLib.sol";
import {MarginAccount} from "../src/MarginAccount.sol";
import {FundingOracle} from "../src/FundingOracle.sol";
import {InsuranceFund} from "../src/InsuranceFund.sol";

import {MockUSDC} from "./utils/mocks/MockUSDC.sol";
import {MockVETH} from "./utils/mocks/MockVETH.sol";
import {MockHook} from "./utils/mocks/MockHook.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {MockPyth} from "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";

contract LiquidationEngineTest is Test {
    using PoolIdLibrary for PoolId;

    LiquidationEngine liquidationEngine;
    PositionManager positionManager2;
    PositionFactory positionFactory;
    PositionNFT positionNFT;
    MarketManager marketManager;
    MarginAccount marginAccount;
    FundingOracle fundingOracle;
    InsuranceFund insuranceFund;
    MockUSDC usdc;
    MockVETH veth;
    MockPyth mockPyth;
    MockHook mockHook;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address liquidator = makeAddr("liquidator");
    address treasury = makeAddr("treasury");

    PoolId testPoolId;
    uint256 aliceTokenId;
    
    bytes32 constant ETH_USD_FEED_ID = 0x736999a0e4eb5f0971f3284ae492df38662f96f28c957f1417ec42f211a7f7eb;

    function setUp() public {
        // Deploy mock tokens
        usdc = new MockUSDC();
        veth = new MockVETH();
        mockPyth = new MockPyth(60, 1);
        mockHook = new MockHook();

        // Deploy system contracts
        marginAccount = new MarginAccount(address(usdc));
        positionFactory = new PositionFactory(address(usdc), address(marginAccount));
        positionNFT = new PositionNFT();
        marketManager = new MarketManager();
        insuranceFund = new InsuranceFund(address(usdc));
        fundingOracle = new FundingOracle(address(mockPyth));
        positionManager2 = new PositionManager(
            address(positionFactory),
            address(positionNFT),
            address(marketManager)
        );

        // Setup modular component authorizations
        positionFactory.setPositionNFT(address(positionNFT));
        positionNFT.setFactory(address(positionFactory));
        
        // Transfer ownership of modular components to PositionManager
        positionFactory.transferOwnership(address(positionManager2));
        marketManager.transferOwnership(address(positionManager2));

        // Deploy LiquidationEngine
        liquidationEngine = new LiquidationEngine(
            address(positionManager2),
            address(positionFactory),
            address(marginAccount),
            address(fundingOracle),
            payable(address(insuranceFund)),
            address(usdc)
        );

        // Setup contract authorizations
        marginAccount.addAuthorizedContract(address(positionManager2));
        marginAccount.addAuthorizedContract(address(positionFactory));
        marginAccount.addAuthorizedContract(address(liquidationEngine));
        insuranceFund.addAuthorizedContract(address(positionManager2));
        insuranceFund.addAuthorizedContract(address(liquidationEngine));

        // Setup test pool
        testPoolId = PoolId.wrap(keccak256("TEST_POOL"));
        positionManager2.addMarket(
            PoolId.unwrap(testPoolId),
            address(veth),    // base asset
            address(usdc),    // quote asset  
            address(mockHook) // pool address
        );
        
        // Add market to funding oracle
        fundingOracle.addMarket(testPoolId, address(mockHook), ETH_USD_FEED_ID);

        // Setup mock hook with initial price
        mockHook.setMarkPrice(PoolId.unwrap(testPoolId), 2000e18); // $2000 ETH
        mockHook.setMarketActive(PoolId.unwrap(testPoolId), true);

        // Setup liquidation config
        liquidationEngine.configureLiquidation(
            PoolId.unwrap(testPoolId),
            500,  // 5% maintenance margin
            50,   // 0.5% liquidation fee
            25,   // 0.25% insurance fee
            true  // active
        );

        // Mint tokens to test users
        usdc.mint(alice, 10000e6);
        usdc.mint(bob, 10000e6);
        usdc.mint(liquidator, 10000e6);

        // Setup allowances
        vm.prank(alice);
        usdc.approve(address(marginAccount), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(marginAccount), type(uint256).max);
        vm.prank(liquidator);
        usdc.approve(address(marginAccount), type(uint256).max);

        // Deposit initial margin
        vm.prank(alice);
        marginAccount.deposit(1000e6);

        // Create a test position for Alice
        vm.prank(alice);
        aliceTokenId = positionManager2.openPosition(
            PoolId.unwrap(testPoolId),  // marketId
            int256(1e18),               // sizeBase (1 ETH long)
            2000e18,                    // entryPrice ($2000)
            200e6                       // margin (200 USDC) -> 10x leverage
        );
    }

    function test_deployment() public {
        assertEq(address(liquidationEngine.positionManager()), address(positionManager2));
        assertEq(address(liquidationEngine.marginAccount()), address(marginAccount));
        assertEq(address(liquidationEngine.fundingOracle()), address(fundingOracle));
        assertEq(address(liquidationEngine.insuranceFund()), address(insuranceFund));
        assertEq(address(liquidationEngine.USDC()), address(usdc));
        
        assertEq(liquidationEngine.minLiquidationSize(), 1e6);
        assertEq(liquidationEngine.maxPositionsPerCheck(), 50);
        assertEq(liquidationEngine.DEFAULT_MAINTENANCE_MARGIN_RATIO(), 500);
        assertEq(liquidationEngine.DEFAULT_LIQUIDATION_FEE_RATE(), 50);
        assertEq(liquidationEngine.DEFAULT_INSURANCE_FEE_RATE(), 25);
    }

    function test_configureLiquidation() public {
        bytes32 marketId = keccak256("NEW_MARKET");
        
        vm.expectEmit(true, false, false, true);
        emit LiquidationEngine.LiquidationConfigUpdated(marketId, 600, 75, 50, true);
        
        liquidationEngine.configureLiquidation(marketId, 600, 75, 50, true);
        
        LiquidationEngine.LiquidationConfig memory config = 
            liquidationEngine.getLiquidationConfig(marketId);
            
        assertEq(config.maintenanceMarginRatio, 600);
        assertEq(config.liquidationFeeRate, 75);
        assertEq(config.insuranceFeeRate, 50);
        assertTrue(config.isActive);
    }

    function test_configureLiquidation_revert_non_owner() public {
        bytes32 marketId = keccak256("NEW_MARKET");
        
        vm.prank(alice);
        vm.expectRevert();
        liquidationEngine.configureLiquidation(marketId, 600, 75, 50, true);
    }

    function test_isPositionLiquidatable_healthy_position() public {
        // Set mock price at entry price (no PnL)
        _setPythPrice(ETH_USD_FEED_ID, 2000e18);
        
        (bool isLiquidatable, uint256 currentPrice, uint256 healthFactor) = 
            liquidationEngine.isPositionLiquidatable(aliceTokenId);
            
        assertFalse(isLiquidatable);
        assertEq(currentPrice, 2000e18);
        assertGt(healthFactor, 1e18); // > 100% health
    }

    function test_isPositionLiquidatable_underwater_position() public {
        // Set price significantly below entry to trigger liquidation
        _setPythPrice(ETH_USD_FEED_ID, 1600e18); // 20% drop
        
        (bool isLiquidatable, uint256 currentPrice, uint256 healthFactor) = 
            liquidationEngine.isPositionLiquidatable(aliceTokenId);
            
        assertTrue(isLiquidatable);
        assertEq(currentPrice, 1600e18);
        assertLt(healthFactor, 1e18); // < 100% health
    }

    function test_liquidatePosition_successful() public {
        // Set price to trigger liquidation
        _setPythPrice(ETH_USD_FEED_ID, 1600e18);
        
        uint256 liquidatorBalanceBefore = usdc.balanceOf(liquidator);
        uint256 insuranceBalanceBefore = usdc.balanceOf(address(insuranceFund));
        
        vm.expectEmit(true, true, true, false);
        emit LiquidationEngine.PositionLiquidated(
            aliceTokenId,
            liquidator,
            alice,
            PoolId.unwrap(testPoolId),
            1600e18,
            1e18, // 1 ETH position size
            0, // PnL (approximated)
            0, // liquidation fee (approximated)
            0  // insurance fee (approximated)
        );
        
        vm.prank(liquidator);
        liquidationEngine.liquidatePosition(aliceTokenId);
        
        // Check position was removed
        PositionLib.Position memory position = positionManager2.getPosition(aliceTokenId);
        assertEq(position.owner, address(0));
        
        // Check liquidator received fee
        assertGt(usdc.balanceOf(liquidator), liquidatorBalanceBefore);
        
        // Check insurance fund received fee
        assertGt(usdc.balanceOf(address(insuranceFund)), insuranceBalanceBefore);
    }

    function test_liquidatePosition_revert_position_not_found() public {
        uint256 nonExistentTokenId = 999;
        
        vm.prank(liquidator);
        vm.expectRevert(LiquidationEngine.PositionNotFound.selector);
        liquidationEngine.liquidatePosition(nonExistentTokenId);
    }

    function test_liquidatePosition_revert_position_healthy() public {
        // Keep price at entry level (healthy position)
        _setPythPrice(ETH_USD_FEED_ID, 2000e18);
        
        vm.prank(liquidator);
        vm.expectRevert(LiquidationEngine.PositionNotLiquidatable.selector);
        liquidationEngine.liquidatePosition(aliceTokenId);
    }

    function test_liquidatePosition_revert_market_not_configured() public {
        // Create position in unconfigured market
        PoolId newPoolId = PoolId.wrap(keccak256("UNCONFIGURED_POOL"));
        positionManager2.addMarket(
            PoolId.unwrap(newPoolId),
            address(veth),
            address(usdc),
            address(mockHook)
        );
        
        vm.prank(alice);
        uint256 tokenId = positionManager2.openPosition(
            PoolId.unwrap(newPoolId),  // marketId
            int256(1e18),              // sizeBase (1 ETH long)
            2000e18,                   // entryPrice ($2000)
            200e6                      // margin (200 USDC) -> 10x leverage
        );
        
        vm.prank(liquidator);
        vm.expectRevert(LiquidationEngine.MarketNotConfigured.selector);
        liquidationEngine.liquidatePosition(tokenId);
    }

    function test_liquidatePosition_revert_liquidations_disabled() public {
        // Disable liquidations for the market
        liquidationEngine.configureLiquidation(
            PoolId.unwrap(testPoolId),
            500,
            50,
            25,
            false // disabled
        );
        
        // Set price to trigger liquidation
        _setPythPrice(ETH_USD_FEED_ID, 1600e18);
        
        vm.prank(liquidator);
        vm.expectRevert(LiquidationEngine.LiquidationsDisabled.selector);
        liquidationEngine.liquidatePosition(aliceTokenId);
    }

    function test_liquidatePositions_batch() public {
        // Create multiple positions for Alice
        vm.startPrank(alice);
        uint256 tokenId2 = positionManager2.openPosition(
            PoolId.unwrap(testPoolId),  // marketId
            int256(0.8e18),             // sizeBase (0.8 ETH long)
            2000e18,                    // entryPrice ($2000)
            160e6                       // margin (160 USDC) -> 10x leverage
        );
        uint256 tokenId3 = positionManager2.openPosition(
            PoolId.unwrap(testPoolId),  // marketId
            int256(0.6e18),             // sizeBase (0.6 ETH long)
            2000e18,                    // entryPrice ($2000)
            120e6                       // margin (120 USDC) -> 10x leverage
        );
        vm.stopPrank();
        
        // Set price to trigger liquidation
        _setPythPrice(ETH_USD_FEED_ID, 1600e18);
        
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = aliceTokenId;
        tokenIds[1] = tokenId2;
        tokenIds[2] = tokenId3;
        
        vm.prank(liquidator);
        liquidationEngine.liquidatePositions(tokenIds);
        
        // Check all positions were liquidated
        PositionLib.Position memory pos1 = positionManager2.getPosition(aliceTokenId);
        PositionLib.Position memory pos2 = positionManager2.getPosition(tokenId2);
        PositionLib.Position memory pos3 = positionManager2.getPosition(tokenId3);
        
        assertEq(pos1.owner, address(0));
        assertEq(pos2.owner, address(0));
        assertEq(pos3.owner, address(0));
    }

    function test_liquidatePositions_batch_revert_too_many() public {
        uint256[] memory tokenIds = new uint256[](51); // Exceeds maxPositionsPerCheck
        
        vm.prank(liquidator);
        vm.expectRevert("Too many positions");
        liquidationEngine.liquidatePositions(tokenIds);
    }

    function test_liquidatePositions_batch_revert_no_liquidations() public {
        // Healthy positions shouldn't be liquidated
        _setPythPrice(ETH_USD_FEED_ID, 2000e18);
        
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = aliceTokenId;
        
        vm.prank(liquidator);
        vm.expectRevert("No positions liquidated");
        liquidationEngine.liquidatePositions(tokenIds);
    }

    function test_setMinLiquidationSize() public {
        uint256 newSize = 5e6; // $5 minimum
        
        liquidationEngine.setMinLiquidationSize(newSize);
        assertEq(liquidationEngine.minLiquidationSize(), newSize);
    }

    function test_setMinLiquidationSize_revert_non_owner() public {
        vm.prank(alice);
        vm.expectRevert();
        liquidationEngine.setMinLiquidationSize(5e6);
    }

    function test_setMaxPositionsPerCheck() public {
        uint256 newMax = 100;
        
        liquidationEngine.setMaxPositionsPerCheck(newMax);
        assertEq(liquidationEngine.maxPositionsPerCheck(), newMax);
    }

    function test_setMaxPositionsPerCheck_revert_non_owner() public {
        vm.prank(alice);
        vm.expectRevert();
        liquidationEngine.setMaxPositionsPerCheck(100);
    }

    function test_getLiquidationHistory() public {
        // Set price to trigger liquidation
        _setPythPrice(ETH_USD_FEED_ID, 1600e18);
        
        vm.prank(liquidator);
        liquidationEngine.liquidatePosition(aliceTokenId);
        
        // Check liquidation was recorded
        LiquidationEngine.LiquidationInfo memory info = 
            liquidationEngine.getLiquidationInfo(aliceTokenId);
        
        assertEq(info.tokenId, aliceTokenId);
        assertEq(info.liquidator, liquidator);
        assertEq(info.positionOwner, alice);
        assertEq(info.liquidationPrice, 1600e18);
        assertEq(info.positionSize, 1e18);
        assertGt(info.timestamp, 0);
        
        // Check total liquidations count
        assertEq(liquidationEngine.getTotalLiquidations(), 1);
    }

    function test_getTotalLiquidations() public {
        // Initially no liquidations
        assertEq(liquidationEngine.getTotalLiquidations(), 0);
        
        // Set price to trigger liquidation
        _setPythPrice(ETH_USD_FEED_ID, 1600e18);
        
        vm.prank(liquidator);
        liquidationEngine.liquidatePosition(aliceTokenId);
        
        // Should have 1 liquidation
        assertEq(liquidationEngine.getTotalLiquidations(), 1);
    }

    function testFuzz_liquidation_thresholds(uint256 priceDropBps) public {
        // Bound price drop to reasonable range (0-90% drop)
        priceDropBps = bound(priceDropBps, 0, 9000);
        
        uint256 newPrice = 2000e18 - (2000e18 * priceDropBps / 10000);
        _setPythPrice(ETH_USD_FEED_ID, newPrice);
        
        (bool isLiquidatable,,) = liquidationEngine.isPositionLiquidatable(aliceTokenId);
        
        // Position should be liquidatable if price dropped significantly
        // Given 5x leverage and 5% maintenance margin, position becomes liquidatable 
        // when price drops by ~20% (100/5 - 5 = 15% margin left)
        if (priceDropBps >= 2000) { // 20% drop
            assertTrue(isLiquidatable);
        }
    }

    function test_liquidation_fee_distribution() public {
        uint256 liquidatorBalanceBefore = usdc.balanceOf(liquidator);
        uint256 insuranceBalanceBefore = insuranceFund.getBalance();
        
        // Set price to trigger liquidation
        _setPythPrice(ETH_USD_FEED_ID, 1600e18);
        
        vm.prank(liquidator);
        liquidationEngine.liquidatePosition(aliceTokenId);
        
        // Check fees were distributed
        uint256 liquidatorFee = usdc.balanceOf(liquidator) - liquidatorBalanceBefore;
        uint256 insuranceFee = insuranceFund.getBalance() - insuranceBalanceBefore;
        
        assertGt(liquidatorFee, 0);
        assertGt(insuranceFee, 0);
        
        // Liquidator fee should be higher than insurance fee (0.5% vs 0.25%)
        assertGt(liquidatorFee, insuranceFee);
    }

    // Helper function to set Pyth price
    function _setPythPrice(bytes32 priceId, uint256 price) internal {
        int64 pythPrice = int64(uint64(price / 1e10)); // 8 decimals
        int32 expo = -8;
        uint64 conf = uint64(price / 1e12); // 1% confidence
        
        bytes memory updateData = mockPyth.createPriceFeedUpdateData(
            priceId,
            pythPrice,
            conf,
            expo,
            pythPrice,
            conf,
            uint64(block.timestamp),
            uint64(block.timestamp) - 1
        );
        
        bytes[] memory updateDataArray = new bytes[](1);
        updateDataArray[0] = updateData;
        
        uint updateFee = mockPyth.getUpdateFee(updateDataArray);
        mockPyth.updatePriceFeeds{value: updateFee}(updateDataArray);
        
        // Also update the mock hook price
        mockHook.setMarkPrice(PoolId.unwrap(testPoolId), price);
    }
}
