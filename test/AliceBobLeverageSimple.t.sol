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

/// @title AliceBobLeverageDemo - Simple Alice & Bob Leverage Trading with Virtual AMM State
/// @notice Clean demonstration of 2x, 3x leverage scenarios with virtual AMM state tracking
contract AliceBobLeverageDemo is Test {
    /*//////////////////////////////////////////////////////////////
                                MARKET ID
    //////////////////////////////////////////////////////////////*/
    
    // Market identifier for ETH-USDC perps
    bytes32 public constant ETH_USDC_MARKET = keccak256("ETH-USDC");
    
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
    address public david = makeAddr("david");
    address public eve = makeAddr("eve");
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    uint256 public constant INITIAL_ETH_PRICE = 2000e18; // $2,000
    
    /*//////////////////////////////////////////////////////////////
                            VIRTUAL AMM STATE
    //////////////////////////////////////////////////////////////*/
    
    struct VAMMState {
        uint256 virtualBase;    // Virtual base token reserve (ETH)
        uint256 virtualQuote;   // Virtual quote token reserve (USDC) 
        uint256 totalLongOI;    // Total long open interest
        uint256 totalShortOI;   // Total short open interest
        uint256 markPrice;      // Current mark price
    }
    
    VAMMState public vammState;
    
    function setUp() public {
        console.log("=== ALICE BOB LEVERAGE DEMONSTRATION SETUP ===");
        
        // Deploy tokens
        usdc = new MockUSDC();
        veth = new MockVETH();
        
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
        
        // Setup users
        _setupUsers();
        
        // Initialize virtual AMM state
        _initializeVAMM();
        
        console.log("=== SETUP COMPLETE ===");
        console.log("");
    }
    
    function _setupUsers() internal {
        // Mint USDC to users with varying amounts
        usdc.mint(alice, 15000e6);   // $15,000 USDC
        usdc.mint(bob, 25000e6);     // $25,000 USDC
        usdc.mint(charlie, 50000e6); // $50,000 USDC
        usdc.mint(david, 10000e6);   // $10,000 USDC
        usdc.mint(eve, 8000e6);      // $8,000 USDC
        
        // Setup approvals and deposits for all users
        address[] memory users = new address[](5);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;
        users[3] = david;
        users[4] = eve;
        
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 15000e6;
        amounts[1] = 25000e6;
        amounts[2] = 50000e6;
        amounts[3] = 10000e6;
        amounts[4] = 8000e6;
        
        for (uint i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            usdc.approve(address(marginAccount), type(uint256).max);
            marginAccount.deposit(amounts[i]);
            vm.stopPrank();
            
            string memory userName = users[i] == alice ? "Alice" : 
                                   users[i] == bob ? "Bob" : 
                                   users[i] == charlie ? "Charlie" :
                                   users[i] == david ? "David" : "Eve";
            console.log(userName, "deposited: $", amounts[i] / 1e6, "USDC");
        }
        
        // Fund PositionManager for profit payouts
        usdc.mint(address(positionManager), 200000e6);
    }
    
    /*//////////////////////////////////////////////////////////////
                            VIRTUAL AMM FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _initializeVAMM() internal {
        // Initialize virtual AMM with balanced reserves for $2000 ETH price
        vammState.virtualBase = 500e18;     // 500 ETH
        vammState.virtualQuote = 1000000e6; // 1M USDC  
        vammState.totalLongOI = 0;
        vammState.totalShortOI = 0;
        vammState.markPrice = 2000e18;      // $2000 initial price
        
        console.log("Virtual AMM initialized with $2000 ETH price");
    }
    
    function _logVAMMState(string memory description) internal view {
        console.log("--- VIRTUAL AMM STATE:", description, "---");
        console.log("Virtual Base Reserve:", vammState.virtualBase / 1e18, "ETH");
        console.log("Virtual Quote Reserve:", vammState.virtualQuote / 1e6, "USDC");
        console.log("Mark Price: $", vammState.markPrice / 1e18);
        console.log("Total Long OI:", vammState.totalLongOI / 1e18, "ETH");
        console.log("Total Short OI:", vammState.totalShortOI / 1e18, "ETH");
        
        int256 netSkew = int256(vammState.totalLongOI) - int256(vammState.totalShortOI);
        if (netSkew >= 0) {
            console.log("Net Skew: +", uint256(netSkew) / 1e18, "ETH");
        } else {
            console.log("Net Skew: -", uint256(-netSkew) / 1e18, "ETH");
        }
        
        if (netSkew > 0) {
            console.log("Market Bias: LONG HEAVY");
        } else if (netSkew < 0) {
            console.log("Market Bias: SHORT HEAVY");
        } else {
            console.log("Market Bias: BALANCED");
        }
        console.log("---");
    }
    
    function _updateVAMMForTrade(uint256 size, bool isLong) internal {
        if (isLong) {
            // Long position increases long OI and affects price upward
            vammState.totalLongOI += size;
            
            // Simple price impact: each 1 ETH of long OI increases price by $1
            uint256 priceImpact = size / 1e18; // Convert to ETH units
            vammState.markPrice += priceImpact * 1e18; // Add to price
            
            // Update virtual reserves to reflect new price
            vammState.virtualBase -= size;
            uint256 quoteToAdd = (size * vammState.markPrice) / 1e18;
            vammState.virtualQuote += quoteToAdd;
        } else {
            // Short position increases short OI and affects price downward
            vammState.totalShortOI += size;
            
            // Simple price impact: each 1 ETH of short OI decreases price by $1
            uint256 priceImpact = size / 1e18; // Convert to ETH units
            if (vammState.markPrice > priceImpact * 1e18) {
                vammState.markPrice -= priceImpact * 1e18; // Subtract from price
            }
            
            // Update virtual reserves to reflect new price
            vammState.virtualBase += size;
            uint256 quoteToRemove = (size * vammState.markPrice) / 1e18;
            if (vammState.virtualQuote > quoteToRemove) {
                vammState.virtualQuote -= quoteToRemove;
            }
        }
    }
    
    function _logUserState(address user, string memory userName) internal view {
        console.log("--- USER STATE:", userName, "---");
        uint256 availableBalance = marginAccount.getAvailableBalance(user);
        uint256 lockedBalance = marginAccount.getLockedBalance(user);
        uint256 totalBalance = availableBalance + lockedBalance;
        
        console.log("Available Balance: $", availableBalance / 1e6);
        console.log("Locked Balance: $", lockedBalance / 1e6);
        console.log("Total Balance: $", totalBalance / 1e6);
        console.log("---");
    }
    
    function _checkLiquidationStatus(address user, string memory userName) internal view {
        // Get margin account balances
        uint256 totalBalance = marginAccount.getTotalBalance(user);
        uint256 availableBalance = marginAccount.getAvailableBalance(user);
        uint256 lockedBalance = marginAccount.getLockedBalance(user);
        
        // Simple liquidation risk assessment based on available vs locked balance
        uint256 riskRatio = lockedBalance > 0 ? (lockedBalance * 100) / totalBalance : 0;
        bool isHighRisk = riskRatio > 80; // If more than 80% of balance is locked
        
        console.log(userName, "liquidation status:");
        console.log("  Total Balance: $", totalBalance / 1e6);
        console.log("  Available: $", availableBalance / 1e6);
        console.log("  Locked: $", lockedBalance / 1e6);
        console.log("  Risk Ratio: ", riskRatio, "%");
        console.log("  High Risk: ", isHighRisk ? "YES" : "NO");
    }
    
    /*//////////////////////////////////////////////////////////////
                            UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function abs(int256 x) internal pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }
    
    function signedToString(int256 value) internal pure returns (string memory) {
        if (value >= 0) {
            return string(abi.encodePacked("+", uint256(value)));
        } else {
            return string(abi.encodePacked("-", uint256(-value)));
        }
    }
    
    function _printVammState(string memory description) internal view {
        _logVAMMState(description);
    }
    
    function _printPositionPnL(address user, string memory userName) internal view {
        console.log(userName, "Position Summary:");
        
        uint256 totalBalance = marginAccount.getTotalBalance(user);
        uint256 availableBalance = marginAccount.getAvailableBalance(user);
        uint256 lockedBalance = marginAccount.getLockedBalance(user);
        
        console.log("  Total Balance: $", totalBalance / 1e6);
        console.log("  Available: $", availableBalance / 1e6);
        console.log("  Locked (in positions): $", lockedBalance / 1e6);
        
        if (lockedBalance > 0) {
            uint256 leverageRatio = totalBalance > 0 ? (lockedBalance * 10) / totalBalance : 0;
            console.log("  Estimated Leverage: ~", leverageRatio / 10, "x");
        }
    }
    
    /*//////////////////////////////////////////////////////////////
                        MAIN DEMONSTRATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testAliceBobLeverageDemo() public {
        console.log("\n=== ALICE & BOB LEVERAGE DEMO ===");
        
        _printVammState("Initial VAMM State");
        
        // Alice opens 2x long position
        vm.startPrank(alice);
        int256 aliceCollateral = 5000e6;  // $5,000 collateral
        int256 aliceSize = 5e18;  // 5 ETH position = 2x leverage at $2000/ETH
        positionManager.openPosition(ETH_USDC_MARKET, aliceSize, INITIAL_ETH_PRICE, uint256(aliceCollateral));
        vm.stopPrank();
        
        console.log("Alice opens 2x LONG position:");
        console.log("  Collateral: $", uint256(aliceCollateral) / 1e6);
        console.log("  Position Size: ", uint256(aliceSize) / 1e18, "ETH");
        console.log("  Leverage: ~2x");
        _printVammState("After Alice Long Position");
        
        // Bob opens 3x short position
        vm.startPrank(bob);
        int256 bobCollateral = 6667e6;  // $6,667 collateral
        int256 bobSize = -10e18;  // -10 ETH position = 3x leverage
        positionManager.openPosition(ETH_USDC_MARKET, bobSize, INITIAL_ETH_PRICE, uint256(bobCollateral));
        vm.stopPrank();
        
        console.log("Bob opens 3x SHORT position:");
        console.log("  Collateral: $", uint256(bobCollateral) / 1e6);
        console.log("  Position Size: ", uint256(abs(bobSize)) / 1e18, "ETH SHORT");
        console.log("  Leverage: ~3x");
        _printVammState("After Bob Short Position");
        
        // Show position PnL
        _printPositionPnL(alice, "Alice");
        _printPositionPnL(bob, "Bob");
    }
    
    function test_AliceBobLeverageDemo() public {
        console.log("=== ALICE BOB LEVERAGE TRADING DEMONSTRATION ===");
        console.log("");
        
        // Show initial states
        _logVAMMState("INITIAL");
        _logUserState(alice, "ALICE INITIAL");
        _logUserState(bob, "BOB INITIAL");
        console.log("");
        
        // STEP 1: Alice opens 2x long
        _aliceOpens2xLong();
        
        // STEP 2: Bob opens 3x short  
        _bobOpens3xShort();
        
        // STEP 3: Show price impact demonstration
        _demonstratePriceMovements();
        
        console.log("=== DEMONSTRATION COMPLETE ===");
    }
    
    function _aliceOpens2xLong() internal {
        console.log("STEP 1: Alice Opens 2x Leveraged Long Position");
        console.log("============================================");
        
        // Alice wants 2x leverage with $5,000 margin
        // This controls $10,000 worth of ETH = 5 ETH at $2,000
        uint256 margin = 5000e6; // $5,000 margin
        int256 ethSize = 5e18;   // 5 ETH for 2x leverage
        uint256 entryPrice = vammState.markPrice;
        
        console.log("Alice's Trade Plan:");
        console.log("  Margin: $", margin / 1e6);
        console.log("  Leverage: 2x");
        console.log("  Position Size: 5 ETH");
        console.log("  Entry Price: $", entryPrice / 1e18);
        console.log("  Position Value: $", (uint256(ethSize) * entryPrice) / 1e18 / 1e18);
        console.log("");
        
        // Show vAMM state before trade
        _logVAMMState("BEFORE ALICE TRADE");
        
        // Alice opens position
        vm.prank(alice);
        uint256 aliceTokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            ethSize,
            entryPrice,
            margin
        );
        
        console.log("Alice opened position #", aliceTokenId);
        
        // Update vAMM state to simulate the trade impact
        _updateVAMMForTrade(uint256(ethSize), true); // Long position
        
        // Show vAMM state after trade
        _logVAMMState("AFTER ALICE TRADE");
        _logUserState(alice, "ALICE AFTER TRADE");
        console.log("");
    }
    
    function _bobOpens3xShort() internal {
        console.log("STEP 2: Bob Opens 3x Leveraged Short Position");
        console.log("==========================================");
        
        // Bob wants 3x leverage short with $6,000 margin
        // This controls $18,000 worth of ETH = ~9 ETH at current price
        uint256 margin = 6000e6; // $6,000 margin
        uint256 currentPrice = vammState.markPrice;
        uint256 positionValue = margin * 3; // $18,000
        uint256 ethAmount = (positionValue * 1e18) / currentPrice; // Calculate ETH amount
        int256 ethSize = -int256(ethAmount); // Negative for short
        
        console.log("Bob's Trade Plan:");
        console.log("  Margin: $", margin / 1e6);
        console.log("  Leverage: 3x");
        console.log("  Position Size:", ethAmount / 1e18, "ETH (SHORT)");
        console.log("  Entry Price: $", currentPrice / 1e18);
        console.log("  Position Value: $", positionValue / 1e6);
        console.log("");
        
        // Show vAMM state before trade
        _logVAMMState("BEFORE BOB TRADE");
        
        // Bob opens position
        vm.prank(bob);
        uint256 bobTokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            ethSize,
            currentPrice,
            margin
        );
        
        console.log("Bob opened position #", bobTokenId);
        
        // Update vAMM state to simulate the trade impact
        _updateVAMMForTrade(ethAmount, false); // Short position
        
        // Show vAMM state after trade
        _logVAMMState("AFTER BOB TRADE");
        _logUserState(bob, "BOB AFTER TRADE");
        console.log("");
    }
    
    function _demonstratePriceMovements() internal {
        console.log("STEP 3: Price Movement Analysis");
        console.log("=============================");
        
        uint256 currentPrice = vammState.markPrice;
        console.log("Current Mark Price: $", currentPrice / 1e18);
        console.log("");
        
        console.log("SCENARIO ANALYSIS:");
        console.log("");
        
        console.log("IF ETH PRICE MOVES TO $2,200 (+", ((2200e18 - INITIAL_ETH_PRICE) * 100) / INITIAL_ETH_PRICE, "%):");
        console.log("  Alice (2x long, 5 ETH): Profit = 5 ETH * $200 = $1,000");
        console.log("  Alice Return on Margin: +", (1000 * 100) / 5000, "%");
        console.log("");
        console.log("  Bob (3x short, ~9 ETH): Loss = 9 ETH * $200 = $1,800");
        console.log("  Bob Return on Margin: -", (1800 * 100) / 6000, "%");
        console.log("");
        
        console.log("IF ETH PRICE MOVES TO $1,800 (-", ((INITIAL_ETH_PRICE - 1800e18) * 100) / INITIAL_ETH_PRICE, "%):");
        console.log("  Alice (2x long, 5 ETH): Loss = 5 ETH * $200 = $1,000");
        console.log("  Alice Return on Margin: -", (1000 * 100) / 5000, "%");
        console.log("");
        console.log("  Bob (3x short, ~9 ETH): Profit = 9 ETH * $200 = $1,800");
        console.log("  Bob Return on Margin: +", (1800 * 100) / 6000, "%");
        console.log("");
        
        console.log("VIRTUAL AMM MECHANICS:");
        console.log("  Long trades: Decrease virtual base, increase virtual quote (price up)");
        console.log("  Short trades: Increase virtual base, decrease virtual quote (price down)");
        console.log("  Net long bias: Market premium to spot price");
        console.log("  Net short bias: Market discount to spot price");
        console.log("");
        
        // Final state summary
        _logVAMMState("FINAL STATE");
        _logUserState(alice, "ALICE FINAL");
        _logUserState(bob, "BOB FINAL");
    }
    
    function testHighLeverageScenarios() public {
        console.log("\n=== HIGH LEVERAGE SCENARIOS ===");
        
        _printVammState("Initial VAMM State");
        
        // Charlie opens 5x long position
        vm.startPrank(charlie);
        int256 charlieCollateral = 10000e6;  // $10,000
        int256 charlieSize = 25e18;  // 25 ETH position = 5x leverage
        positionManager.openPosition(ETH_USDC_MARKET, charlieSize, INITIAL_ETH_PRICE, uint256(charlieCollateral));
        vm.stopPrank();
        
        console.log("Charlie opens 5x LONG position:");
        console.log("  Collateral: $", uint256(charlieCollateral) / 1e6);
        console.log("  Position Size: ", uint256(charlieSize) / 1e18, "ETH");
        console.log("  Leverage: 5x");
        _printVammState("After Charlie 5x Long");
        
        // David opens 10x short position  
        vm.startPrank(david);
        int256 davidCollateral = 5000e6;   // $5,000
        int256 davidSize = -25e18;  // -25 ETH position = 10x leverage
        positionManager.openPosition(ETH_USDC_MARKET, davidSize, INITIAL_ETH_PRICE, uint256(davidCollateral));
        vm.stopPrank();
        
        console.log("David opens 10x SHORT position:");
        console.log("  Collateral: $", uint256(davidCollateral) / 1e6);
        console.log("  Position Size: ", uint256(abs(davidSize)) / 1e18, "ETH SHORT");
        console.log("  Leverage: 10x");
        _printVammState("After David 10x Short");
        
        // Eve opens extreme 20x long position
        vm.startPrank(eve);
        int256 eveCollateral = 2000e6;   // $2,000
        int256 eveSize = 20e18;   // 20 ETH position = 20x leverage
        positionManager.openPosition(ETH_USDC_MARKET, eveSize, INITIAL_ETH_PRICE, uint256(eveCollateral));
        vm.stopPrank();
        
        console.log("Eve opens 20x LONG position:");
        console.log("  Collateral: $", uint256(eveCollateral) / 1e6);
        console.log("  Position Size: ", uint256(eveSize) / 1e18, "ETH");
        console.log("  Leverage: 20x");
        _printVammState("After Eve 20x Long");
        
        // Show position details for all high leverage traders
        _printPositionPnL(charlie, "Charlie (5x Long)");
        _printPositionPnL(david, "David (10x Short)");
        _printPositionPnL(eve, "Eve (20x Long)");
    }
    
    function testLiquidationScenarios() public {
        console.log("\n=== LIQUIDATION SCENARIOS ===");
        
        // Setup risky positions
        vm.startPrank(charlie);
        positionManager.openPosition(ETH_USDC_MARKET, 15e18, INITIAL_ETH_PRICE, 3000e6);  // 5x leverage
        vm.stopPrank();
        
        vm.startPrank(david);
        positionManager.openPosition(ETH_USDC_MARKET, -20e18, INITIAL_ETH_PRICE, 2000e6);  // 10x leverage  
        vm.stopPrank();
        
        console.log("Risky positions opened:");
        console.log("Charlie: 5x long (15 ETH, $3000 collateral)");
        console.log("David: 10x short (-20 ETH, $2000 collateral)");
        _printVammState("Before Price Movement");
        
        // Large trade by Eve to move price dramatically
        vm.startPrank(eve);
        positionManager.openPosition(ETH_USDC_MARKET, 40e18, INITIAL_ETH_PRICE, 6000e6);  // Massive long
        vm.stopPrank();
        
        console.log("Eve makes massive 40 ETH long trade to move price up");
        _printVammState("After Massive Long Trade");
        
        // Check if positions are liquidatable
        _checkLiquidationStatus(charlie, "Charlie");
        _checkLiquidationStatus(david, "David");
        _checkLiquidationStatus(eve, "Eve");
        
        // Simulate liquidation by checking margin requirements
        console.log("\nLiquidation Analysis:");
        console.log("Positions with high leverage are vulnerable to liquidation");
        console.log("when unrealized losses exceed margin maintenance requirements");
    }
    
    function testCascadingEffects() public {
        console.log("\n=== CASCADING MARKET EFFECTS ===");
        
        _printVammState("Initial State");
        
        // Series of escalating trades
        console.log("Round 1: Small positions");
        vm.prank(alice);
        positionManager.openPosition(ETH_USDC_MARKET, 2e18, INITIAL_ETH_PRICE, 2000e6);
        _printVammState("After Alice 2 ETH");
        
        console.log("Round 2: Medium positions");
        vm.prank(bob);
        positionManager.openPosition(ETH_USDC_MARKET, -4e18, INITIAL_ETH_PRICE, 3000e6);
        _printVammState("After Bob -4 ETH");
        
        console.log("Round 3: Large positions");
        vm.prank(charlie);
        positionManager.openPosition(ETH_USDC_MARKET, 10e18, INITIAL_ETH_PRICE, 4000e6);
        _printVammState("After Charlie 10 ETH");
        
        console.log("Round 4: Extreme positions");
        vm.prank(david);
        positionManager.openPosition(ETH_USDC_MARKET, -15e18, INITIAL_ETH_PRICE, 2000e6);
        _printVammState("After David -15 ETH");
        
        console.log("Round 5: Market shock");
        vm.prank(eve);
        positionManager.openPosition(ETH_USDC_MARKET, 30e18, INITIAL_ETH_PRICE, 4000e6);
        _printVammState("Final State After Market Shock");
        
        console.log("\nFinal PnL Summary:");
        _printPositionPnL(alice, "Alice");
        _printPositionPnL(bob, "Bob");
        _printPositionPnL(charlie, "Charlie");
        _printPositionPnL(david, "David");
        _printPositionPnL(eve, "Eve");
    }
}
