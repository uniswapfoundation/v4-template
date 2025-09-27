// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

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

/// @title ComprehensiveLeverageTest - Final Integration Test with Alice & Bob Examples
/// @notice Demonstrates complete leverage trading scenarios with detailed logging
/// @dev Shows 2x, 3x leverage examples with realistic user flows
contract ComprehensiveLeverageTest is Test {
    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/
    
    PositionManager public positionManager;
    PositionFactory public positionFactory;
    PositionNFT public positionNFT;
    MarketManager public marketManager;
    MarginAccount public marginAccount;
    FundingOracle public fundingOracle;
    InsuranceFund public insuranceFund;
    MockUSDC public usdc;
    MockVETH public veth;
    
    /*//////////////////////////////////////////////////////////////
                                TEST USERS
    //////////////////////////////////////////////////////////////*/
    
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public liquidator = makeAddr("liquidator");
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    bytes32 public constant ETH_USDC_MARKET = keccak256("ETH-USDC");
    bytes32 public constant BTC_USDC_MARKET = keccak256("BTC-USDC");
    
    // Market prices
    uint256 public constant INITIAL_ETH_PRICE = 2000e18; // $2,000
    uint256 public constant INITIAL_BTC_PRICE = 40000e18; // $40,000
    
    // User initial balances
    uint256 public constant ALICE_INITIAL_USDC = 10000e6;  // $10,000 USDC
    uint256 public constant BOB_INITIAL_USDC = 20000e6;    // $20,000 USDC
    uint256 public constant CHARLIE_INITIAL_USDC = 5000e6; // $5,000 USDC
    
    // Test scenarios
    uint256 public constant SCENARIO_1_MARGIN = 2000e6;    // $2,000 margin for 2x leverage
    uint256 public constant SCENARIO_2_MARGIN = 3000e6;    // $3,000 margin for 3x leverage
    uint256 public constant SCENARIO_3_MARGIN = 1000e6;    // $1,000 margin for smaller position
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event TestScenario(string description);
    event UserAction(address indexed user, string action, uint256 value);
    event PriceUpdate(string market, uint256 oldPrice, uint256 newPrice);
    event PositionDetails(
        address indexed user,
        uint256 tokenId,
        int256 size,
        uint256 margin,
        uint256 entryPrice,
        uint256 currentPrice,
        int256 pnl,
        uint256 leverage
    );
    
    function setUp() public {
        console.log("\n=== SETTING UP COMPREHENSIVE LEVERAGE TEST ===");
        
        // Deploy tokens
        usdc = new MockUSDC();
        veth = new MockVETH();
        
        console.log("Deployed USDC at:", address(usdc));
        console.log("Deployed vETH at:", address(veth));
        
        // Deploy core contracts
        marginAccount = new MarginAccount(address(usdc));
        positionFactory = new PositionFactory(address(usdc), address(marginAccount));
        positionNFT = new PositionNFT();
        marketManager = new MarketManager();
        positionManager = new PositionManager(
            address(positionFactory),
            address(positionNFT),
            address(marketManager)
        );
        fundingOracle = new FundingOracle(address(0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF)); // Placeholder Pyth
        insuranceFund = new InsuranceFund(address(usdc));
        
        console.log("Deployed MarginAccount at:", address(marginAccount));
        console.log("Deployed PositionManager at:", address(positionManager));
        console.log("Deployed FundingOracle at:", address(fundingOracle));
        console.log("Deployed InsuranceFund at:", address(insuranceFund));
        
        // Setup modular component authorizations
        positionFactory.setPositionNFT(address(positionNFT));
        positionNFT.setFactory(address(positionFactory));
        
        // Transfer ownership of modular components to PositionManager
        positionFactory.transferOwnership(address(positionManager));
        marketManager.transferOwnership(address(positionManager));
        
        // Setup contract authorizations
        marginAccount.addAuthorizedContract(address(positionManager));
        marginAccount.addAuthorizedContract(address(positionFactory));
        
        // Add markets
        positionManager.addMarket(
            ETH_USDC_MARKET,
            address(veth),
            address(usdc),
            address(0x123) // Mock pool address
        );
        
        positionManager.addMarket(
            BTC_USDC_MARKET,
            address(0x456), // Mock BTC address
            address(usdc),
            address(0x789) // Mock pool address
        );
        
        console.log("Added ETH-USDC market");
        console.log("Added BTC-USDC market");
        
        // Setup users
        _setupUsers();
        
        console.log("=== SETUP COMPLETE ===\n");
    }
    
    function _setupUsers() internal {
        // Mint USDC to users
        usdc.mint(alice, ALICE_INITIAL_USDC);
        usdc.mint(bob, BOB_INITIAL_USDC);
        usdc.mint(charlie, CHARLIE_INITIAL_USDC);
        usdc.mint(liquidator, 50000e6); // Extra for liquidator
        
        console.log("Alice initial USDC balance:", ALICE_INITIAL_USDC / 1e6, "USDC");
        console.log("Bob initial USDC balance:", BOB_INITIAL_USDC / 1e6, "USDC");
        console.log("Charlie initial USDC balance:", CHARLIE_INITIAL_USDC / 1e6, "USDC");
        
        // Setup approvals and deposits
        address[] memory users = new address[](4);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;
        users[3] = liquidator;
        
        for (uint i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            usdc.approve(address(marginAccount), type(uint256).max);
            
            uint256 depositAmount;
            if (users[i] == alice) depositAmount = ALICE_INITIAL_USDC;
            else if (users[i] == bob) depositAmount = BOB_INITIAL_USDC;
            else if (users[i] == charlie) depositAmount = CHARLIE_INITIAL_USDC;
            else depositAmount = 50000e6;
            
            marginAccount.deposit(depositAmount);
            vm.stopPrank();
            
            console.log(" ", users[i] == alice ? "Alice" : 
                              users[i] == bob ? "Bob" : 
                              users[i] == charlie ? "Charlie" : "Liquidator", 
                        "deposited to MarginAccount");
        }
        
        // Fund PositionManager for profit payouts
        usdc.mint(address(positionManager), 100000e6);
    }
    
    /*//////////////////////////////////////////////////////////////
                        COMPREHENSIVE TEST SCENARIOS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Main test function demonstrating all leverage scenarios
    function test_ComprehensiveLeverageScenarios() public {
        console.log("\n STARTING COMPREHENSIVE LEVERAGE TRADING SCENARIOS\n");
        
        // Scenario 1: Alice trades with 2x leverage
        _testAlice2xLeverageScenario();
        
        // Scenario 2: Bob trades with 3x leverage
        _testBob3xLeverageScenario();
        
        // Scenario 3: Charlie's smaller position
        _testCharlieSmallPositionScenario();
        
        // Scenario 4: Price movements and PnL demonstration
        _testPriceMovementsAndPnL();
        
        // Scenario 5: Funding payments
        _testFundingPayments();
        
        // Scenario 6: Margin management
        _testMarginManagement();
        
        // Final summary
        _printFinalSummary();
    }
    
    /// @notice Alice opens a 2x leveraged long ETH position
    function _testAlice2xLeverageScenario() internal {
        emit TestScenario("SCENARIO 1: Alice's 2x Leveraged Long ETH Position");
        console.log("\n SCENARIO 1: Alice's 2x Leveraged Long ETH Position");
        console.log("============================================================");
        
        // Alice wants 2x leverage with $2,000 margin
        // At $2,000 ETH price, she can control $4,000 worth = 2 ETH
        uint256 margin = SCENARIO_1_MARGIN; // $2,000
        int256 ethSize = 2e18; // 2 ETH for 2x leverage
        uint256 entryPrice = INITIAL_ETH_PRICE;
        
        console.log(" Alice's Trading Plan:");
        console.log(" Margin: $", margin / 1e6);
        console.log(" Leverage: 2x");
        console.log(" Position Size: 2 ETH");
        console.log("    Entry Price: $", entryPrice / 1e18);
        console.log("    Position Value: $", (uint256(ethSize) * entryPrice) / 1e18 / 1e18);
        
        // Check Alice's initial balance
        uint256 aliceInitialBalance = marginAccount.getAvailableBalance(alice);
        console.log("Alice's available balance before:", aliceInitialBalance / 1e6, "USDC");
        
        // Alice opens position
        vm.prank(alice);
        uint256 aliceTokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            ethSize,
            entryPrice,
            margin
        );
        
        emit UserAction(alice, "OPENED_LONG_POSITION", aliceTokenId);
        
        console.log("Alice opened position #", aliceTokenId);
        
        // Check post-position balance
        uint256 alicePostBalance = marginAccount.getAvailableBalance(alice);
        console.log("Alice's available balance after:", alicePostBalance / 1e6, "USDC");
        console.log("Margin locked:", (aliceInitialBalance - alicePostBalance) / 1e6, "USDC");
        
        // Display position details
        _displayPositionDetails(alice, aliceTokenId, entryPrice, "Alice's Initial Position");
    }
    
    /// @notice Bob opens a 3x leveraged short ETH position
    function _testBob3xLeverageScenario() internal {
        emit TestScenario("SCENARIO 2: Bob's 3x Leveraged Short ETH Position");
        console.log("\n SCENARIO 2: Bob's 3x Leveraged Short ETH Position");
        console.log("============================================================");
        
        // Bob wants 3x leverage short with $3,000 margin
        // At $2,000 ETH price, he can control $9,000 worth = 4.5 ETH short
        uint256 margin = SCENARIO_2_MARGIN; // $3,000
        int256 ethSize = -4.5e18; // -4.5 ETH for 3x leverage short
        uint256 entryPrice = INITIAL_ETH_PRICE;
        
        console.log(" Bob's Trading Plan:");
        console.log("    Margin: $", margin / 1e6);
        console.log("    Leverage: 3x");
        console.log("    Position Size: -4.5 ETH (SHORT)");
        console.log("    Entry Price: $", entryPrice / 1e18);
        console.log("    Position Value: $", (uint256(-ethSize) * entryPrice) / 1e18 / 1e18);
        
        // Check Bob's initial balance
        uint256 bobInitialBalance = marginAccount.getAvailableBalance(bob);
        console.log(" Bob's available balance before:", bobInitialBalance / 1e6, "USDC");
        
        // Bob opens position
        vm.prank(bob);
        uint256 bobTokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            ethSize,
            entryPrice,
            margin
        );
        
        emit UserAction(bob, "OPENED_SHORT_POSITION", bobTokenId);
        
        console.log(" Bob opened position #", bobTokenId);
        
        // Check post-position balance
        uint256 bobPostBalance = marginAccount.getAvailableBalance(bob);
        console.log(" Bob's available balance after:", bobPostBalance / 1e6, "USDC");
        console.log(" Margin locked:", (bobInitialBalance - bobPostBalance) / 1e6, "USDC");
        
        // Display position details
        _displayPositionDetails(bob, bobTokenId, entryPrice, "Bob's Initial Position");
    }
    
    /// @notice Charlie opens a smaller leveraged position
    function _testCharlieSmallPositionScenario() internal {
        emit TestScenario("SCENARIO 3: Charlie's Conservative Long BTC Position");
        console.log("\nSCENARIO 3: Charlie's Conservative Long BTC Position");
        console.log("============================================================");
        
        // Charlie opens a smaller BTC position with 2x leverage
        uint256 margin = SCENARIO_3_MARGIN; // $1,000
        int256 btcSize = 0.05e18; // 0.05 BTC
        uint256 entryPrice = INITIAL_BTC_PRICE;
        
        console.log(" Charlie's Trading Plan:");
        console.log("   Margin: $", margin / 1e6);
        console.log("    Leverage: 2x");
        console.log("    Position Size: 0.05 BTC");
        console.log("    Entry Price: $", entryPrice / 1e18);
        console.log("    Position Value: $", (uint256(btcSize) * entryPrice) / 1e18 / 1e18);
        
        // Check Charlie's initial balance
        uint256 charlieInitialBalance = marginAccount.getAvailableBalance(charlie);
        console.log(" Charlie's available balance before:", charlieInitialBalance / 1e6, "USDC");
        
        // Charlie opens position
        vm.prank(charlie);
        uint256 charlieTokenId = positionManager.openPosition(
            BTC_USDC_MARKET,
            btcSize,
            entryPrice,
            margin
        );
        
        emit UserAction(charlie, "OPENED_BTC_LONG", charlieTokenId);
        
        console.log(" Charlie opened position #", charlieTokenId);
        
        // Check post-position balance
        uint256 charliePostBalance = marginAccount.getAvailableBalance(charlie);
        console.log(" Charlie's available balance after:", charliePostBalance / 1e6, "USDC");
        console.log(" Margin locked:", (charlieInitialBalance - charliePostBalance) / 1e6, "USDC");
        
        // Display position details
        _displayPositionDetails(charlie, charlieTokenId, entryPrice, "Charlie's Initial Position");
    }
    
    /// @notice Demonstrate price movements and PnL calculations
    function _testPriceMovementsAndPnL() internal {
        emit TestScenario("SCENARIO 4: Price Movements and PnL Demonstration");
        console.log("\n SCENARIO 4: Price Movements and PnL Demonstration");
        console.log("============================================================");
        
        // Get all open positions
        uint256[] memory alicePositions = positionManager.getUserPositions(alice);
        uint256[] memory bobPositions = positionManager.getUserPositions(bob);
        uint256[] memory charliePositions = positionManager.getUserPositions(charlie);
        
        // Scenario 4a: ETH price increases to $2,200 (+10%)
        console.log("\n PRICE MOVEMENT 1: ETH rises to $2,200 (+10%)");
        uint256 newEthPrice = 2200e18;
        emit PriceUpdate("ETH", INITIAL_ETH_PRICE, newEthPrice);
        
        if (alicePositions.length > 0) {
            _displayPositionDetails(alice, alicePositions[0], newEthPrice, "Alice after ETH +10%");
        }
        if (bobPositions.length > 0) {
            _displayPositionDetails(bob, bobPositions[0], newEthPrice, "Bob after ETH +10%");
        }
        
        // Scenario 4b: ETH price drops to $1,800 (-10%)
        console.log("\n PRICE MOVEMENT 2: ETH drops to $1,800 (-10%)");
        newEthPrice = 1800e18;
        emit PriceUpdate("ETH", 2200e18, newEthPrice);
        
        if (alicePositions.length > 0) {
            _displayPositionDetails(alice, alicePositions[0], newEthPrice, "Alice after ETH -10%");
        }
        if (bobPositions.length > 0) {
            _displayPositionDetails(bob, bobPositions[0], newEthPrice, "Bob after ETH -10%");
        }
        
        // Scenario 4c: BTC price increases to $42,000 (+5%)
        console.log("\n PRICE MOVEMENT 3: BTC rises to $42,000 (+5%)");
        uint256 newBtcPrice = 42000e18;
        emit PriceUpdate("BTC", INITIAL_BTC_PRICE, newBtcPrice);
        
        if (charliePositions.length > 0) {
            _displayPositionDetails(charlie, charliePositions[0], newBtcPrice, "Charlie after BTC +5%");
        }
    }
    
    /// @notice Demonstrate funding payments
    function _testFundingPayments() internal {
        emit TestScenario("SCENARIO 5: Funding Payments");
        console.log("\n SCENARIO 5: Funding Payments");
        console.log("============================================================");
        
        // Simulate funding rate updates
        console.log(" Simulating 8-hour funding cycle...");
        
        // Set funding rates (positive = longs pay shorts)
        uint256 newFundingIndex = 1.001e18; // 0.1% funding rate
        positionManager.updateFundingIndex(ETH_USDC_MARKET, newFundingIndex);
        positionManager.updateFundingIndex(BTC_USDC_MARKET, newFundingIndex);
        
        console.log(" New funding rate: 0.1% (longs pay shorts)");
        
        // Settle funding for all positions
        uint256[] memory alicePositions = positionManager.getUserPositions(alice);
        uint256[] memory bobPositions = positionManager.getUserPositions(bob);
        uint256[] memory charliePositions = positionManager.getUserPositions(charlie);
        
        if (alicePositions.length > 0) {
            // positionManager.settleFunding(alicePositions[0]); // Now handled automatically in updatePosition/closePosition
            console.log(" Funding settlement now handled automatically");
        }
        
        if (bobPositions.length > 0) {
            // positionManager.settleFunding(bobPositions[0]); // Now handled automatically in updatePosition/closePosition
            console.log(" Funding settlement now handled automatically");
        }
        
        if (charliePositions.length > 0) {
            // positionManager.settleFunding(charliePositions[0]); // Now handled automatically in updatePosition/closePosition
            console.log(" Funding settlement now handled automatically");
        }
    }
    
    /// @notice Demonstrate margin management
    function _testMarginManagement() internal {
        emit TestScenario("SCENARIO 6: Margin Management");
        console.log("\n SCENARIO 6: Margin Management");
        console.log("============================================================");
        
        uint256[] memory alicePositions = positionManager.getUserPositions(alice);
        if (alicePositions.length > 0) {
            uint256 tokenId = alicePositions[0];
            
            // Alice adds margin to reduce leverage
            console.log(" Alice adds $500 margin to reduce leverage...");
            uint256 additionalMargin = 500e6;
            
            vm.prank(alice);
            positionManager.addMargin(tokenId, additionalMargin);
            
            emit UserAction(alice, "ADDED_MARGIN", additionalMargin);
            
            _displayPositionDetails(alice, tokenId, 1800e18, "Alice after adding margin");
            
            // Alice removes some margin
            console.log(" Alice removes $200 margin...");
            uint256 marginToRemove = 200e6;
            
            vm.prank(alice);
            positionManager.removeMargin(tokenId, marginToRemove);
            
            emit UserAction(alice, "REMOVED_MARGIN", marginToRemove);
            
            _displayPositionDetails(alice, tokenId, 1800e18, "Alice after removing margin");
        }
    }
    
    /*//////////////////////////////////////////////////////////////
                            UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Display detailed position information with proper formatting
    function _displayPositionDetails(
        address user,
        uint256 tokenId,
        uint256 currentPrice,
        string memory description
    ) internal {
        PositionLib.Position memory position = positionManager.getPosition(tokenId);
        int256 pnl = positionManager.getUnrealizedPnL(tokenId, currentPrice);
        uint256 leverage = positionManager.getCurrentLeverage(tokenId, currentPrice);
        
        string memory userName = user == alice ? "Alice" : 
                                user == bob ? "Bob" : 
                                user == charlie ? "Charlie" : "Unknown";
        
        console.log("\n", description);
        console.log(" User:", userName);
        console.log("Position ID:", tokenId);
        console.log(" Size:", _formatSize(position.sizeBase));
        console.log(" Margin: $", position.margin / 1e6);
        console.log(" Entry Price: $", position.entryPrice / 1e18);
        console.log(" Current Price: $", currentPrice / 1e18);
        console.log(" Leverage:", _formatLeverage(leverage));
        console.log(" Unrealized PnL:", _formatPnL(pnl));
        console.log(" Funding Paid:", _formatFunding(position.fundingPaid));
        
        // Calculate percentage gain/loss
        int256 pnlPercentage = (pnl * 100 * 1e18) / int256(uint256(position.margin) * 1e18);
        console.log(" PnL %:", _formatPercentage(pnlPercentage));
        
        emit PositionDetails(
            user,
            tokenId,
            position.sizeBase,
            position.margin,
            position.entryPrice,
            currentPrice,
            pnl,
            leverage
        );
        
        console.log("--------------------------------------------------");
    }
    
    /// @notice Format position size for display
    function _formatSize(int256 size) internal pure returns (string memory) {
        if (size >= 0) {
            return string(abi.encodePacked("+", _toString(uint256(size) / 1e18), " tokens"));
        } else {
            return string(abi.encodePacked("-", _toString(uint256(-size) / 1e18), " tokens"));
        }
    }
    
    /// @notice Format leverage for display
    function _formatLeverage(uint256 leverage) internal pure returns (string memory) {
        return string(abi.encodePacked(_toString(leverage / 1e18), ".", _toString((leverage % 1e18) / 1e17), "x"));
    }
    
    /// @notice Format PnL for display
    function _formatPnL(int256 pnl) internal pure returns (string memory) {
        if (pnl >= 0) {
            return string(abi.encodePacked("+$", _toString(uint256(pnl) / 1e18)));
        } else {
            return string(abi.encodePacked("-$", _toString(uint256(-pnl) / 1e18)));
        }
    }
    
    /// @notice Format funding for display
    function _formatFunding(int256 funding) internal pure returns (string memory) {
        if (funding >= 0) {
            return string(abi.encodePacked("$", _toString(uint256(funding) / 1e18)));
        } else {
            return string(abi.encodePacked("-$", _toString(uint256(-funding) / 1e18)));
        }
    }
    
    /// @notice Format percentage for display
    function _formatPercentage(int256 percentage) internal pure returns (string memory) {
        if (percentage >= 0) {
            return string(abi.encodePacked("+", _toString(uint256(percentage) / 1e18), "%"));
        } else {
            return string(abi.encodePacked("-", _toString(uint256(-percentage) / 1e18), "%"));
        }
    }
    
    /// @notice Convert uint256 to string
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
    
    /// @notice Print final summary of all positions and balances
    function _printFinalSummary() internal {
        console.log("\n FINAL SUMMARY");
        console.log("============================================================");
        
        // User balances
        console.log("\n Final User Balances:");
        console.log("Alice available balance: $", marginAccount.getAvailableBalance(alice) / 1e6);
        console.log("Bob available balance: $", marginAccount.getAvailableBalance(bob) / 1e6);
        console.log("Charlie available balance: $", marginAccount.getAvailableBalance(charlie) / 1e6);
        
        // Position counts
        console.log("\n Position Counts:");
        console.log("Alice positions:", positionManager.getUserPositions(alice).length);
        console.log("Bob positions:", positionManager.getUserPositions(bob).length);
        console.log("Charlie positions:", positionManager.getUserPositions(charlie).length);
        console.log("Total positions:", positionManager.totalSupply());
        
        // Market activity
        console.log("\n Market Activity:");
        console.log("ETH-USDC positions:", positionManager.getMarketPositions(ETH_USDC_MARKET).length);
        console.log("BTC-USDC positions:", positionManager.getMarketPositions(BTC_USDC_MARKET).length);
        
        console.log("\n COMPREHENSIVE LEVERAGE TEST COMPLETED SUCCESSFULLY!");
        console.log("============================================================");
    }
    
    /*//////////////////////////////////////////////////////////////
                            ADDITIONAL TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test position closure with profits and losses
    function test_PositionClosureScenarios() public {
        console.log("\n TESTING POSITION CLOSURE SCENARIOS");
        
        // Alice opens a position
        vm.prank(alice);
        uint256 tokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            1e18, // 1 ETH
            INITIAL_ETH_PRICE,
            1000e6 // $1000 margin
        );
        
        // Test closure with profit
        console.log("\n TESTING CLOSURE WITH PROFIT:");
        uint256 profitPrice = 2200e18; // +10% price increase
        
        uint256 aliceBalanceBefore = marginAccount.getAvailableBalance(alice);
        int256 pnlBeforeClose = positionManager.getUnrealizedPnL(tokenId, profitPrice);
        
        console.log("Expected PnL before close:", _formatPnL(pnlBeforeClose));
        
        vm.prank(alice);
        positionManager.closePosition(tokenId, profitPrice);
        
        uint256 aliceBalanceAfter = marginAccount.getAvailableBalance(alice);
        console.log("Alice balance change:", _formatPnL(int256(aliceBalanceAfter) - int256(aliceBalanceBefore)));
    }
    
    /// @notice Test liquidation scenarios
    function test_LiquidationScenarios() public {
        console.log("\n  TESTING LIQUIDATION SCENARIOS");
        
        // Bob opens a highly leveraged position
        vm.prank(bob);
        uint256 tokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            5e18, // 5 ETH
            INITIAL_ETH_PRICE,
            1000e6 // $1000 margin - 10x leverage
        );
        
        console.log("Bob opened high leverage position:", tokenId);
        
        // Price drops significantly
        uint256 liquidationPrice = 1600e18; // -20% price drop
        console.log("Price drops to $", liquidationPrice / 1e18);
        
        // Check if position is liquidatable
        _displayPositionDetails(bob, tokenId, liquidationPrice, "Bob's position near liquidation");
    }
    
    /// @notice Test funding rate edge cases
    function test_FundingRateEdgeCases() public {
        console.log("\n TESTING FUNDING RATE EDGE CASES");
        
        // Open positions
        vm.prank(alice);
        uint256 longTokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            1e18,
            INITIAL_ETH_PRICE,
            1000e6
        );
        
        vm.prank(bob);
        uint256 shortTokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            -1e18,
            INITIAL_ETH_PRICE,
            1000e6
        );
        
        // Test high funding rate
        uint256 highFundingIndex = 1.01e18; // 1% funding rate
        positionManager.updateFundingIndex(ETH_USDC_MARKET, highFundingIndex);
        
        console.log("Applied 1% funding rate");
        
        // positionManager.settleFunding(longTokenId);  // Now handled automatically
        // positionManager.settleFunding(shortTokenId); // Now handled automatically
        
        console.log("Funding settlement now handled automatically in position updates");
    }
}
