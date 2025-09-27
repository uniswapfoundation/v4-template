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

/// @title FinalLeverageDemo - Alice & Bob Leverage Trading Demonstration
/// @notice Comprehensive test showing 2x, 3x leverage scenarios with detailed logs
contract FinalLeverageDemo is Test {
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
    
    /*//////////////////////////////////////////////////////////////
                            VIRTUAL AMM STATE
    //////////////////////////////////////////////////////////////*/
    
    // Simulate virtual AMM state for demonstration
    struct VAMMState {
        uint256 virtualBase;    // Virtual base token reserve
        uint256 virtualQuote;   // Virtual quote token reserve  
        uint256 k;              // Constant product (virtualBase * virtualQuote)
        uint256 totalLongOI;    // Total long open interest
        uint256 totalShortOI;   // Total short open interest
        uint256 markPrice;      // Current mark price
    }
    
    VAMMState public vammState;
    
    function setUp() public {
        console.log("=== SETTING UP FINAL LEVERAGE DEMONSTRATION ===");
        
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
        
        console.log("Added ETH-USDC market");
        
        // Setup users
        _setupUsers();
        
        // Initialize virtual AMM state
        _initializeVAMM();
        
        console.log("=== SETUP COMPLETE ===");
        console.log("");
    }
    
    function _setupUsers() internal {
        // Mint USDC to users
        usdc.mint(alice, ALICE_INITIAL_USDC);
        usdc.mint(bob, BOB_INITIAL_USDC);
        usdc.mint(charlie, CHARLIE_INITIAL_USDC);
        
        console.log("Alice initial USDC balance:", ALICE_INITIAL_USDC / 1e6, "USDC");
        console.log("Bob initial USDC balance:", BOB_INITIAL_USDC / 1e6, "USDC");
        console.log("Charlie initial USDC balance:", CHARLIE_INITIAL_USDC / 1e6, "USDC");
        
        // Setup approvals and deposits
        address[] memory users = new address[](3);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;
        
        for (uint i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            usdc.approve(address(marginAccount), type(uint256).max);
            
            uint256 depositAmount;
            if (users[i] == alice) depositAmount = ALICE_INITIAL_USDC;
            else if (users[i] == bob) depositAmount = BOB_INITIAL_USDC;
            else depositAmount = CHARLIE_INITIAL_USDC;
            
            marginAccount.deposit(depositAmount);
            vm.stopPrank();
            
            string memory userName = users[i] == alice ? "Alice" : 
                                   users[i] == bob ? "Bob" : "Charlie";
            console.log(userName, "deposited to MarginAccount");
        }
        
        // Fund PositionManager for profit payouts
        usdc.mint(address(positionManager), 100000e6);
    }
    
    /*//////////////////////////////////////////////////////////////
                            VIRTUAL AMM FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _initializeVAMM() internal {
        // Initialize virtual AMM with smaller reserves to avoid overflow
        // Using 500 vETH base and 1000 USDC quote for $2000 price
        vammState.virtualBase = 500e18;     // 500 vETH
        vammState.virtualQuote = 1000000e6; // 1M USDC (reduced from previous)
        vammState.k = 500 * 1000000; // Simple constant product
        vammState.totalLongOI = 0;
        vammState.totalShortOI = 0;
        
        // Calculate mark price using simple division without overflow risk
        // Price = quote / base (adjusting for decimals)
        // virtualQuote is 1e6, virtualBase is 1e18, want result in 1e18
        // So: (virtualQuote * 1e18) / virtualBase, but avoiding overflow
        // Simplify: (1000000e6 * 1e18) / 500e18 = 1000000e6 / 500 * 1e18 / 1e18 = 2000e6
        // But we want 1e18 precision, so multiply by 1e12: 2000e6 * 1e12 = 2000e18
        vammState.markPrice = 2000e18; // Set directly to $2000 to avoid overflow
        
        console.log("Virtual AMM initialized:");
        console.log("virtualBase:", vammState.virtualBase);
        console.log("virtualQuote:", vammState.virtualQuote);
        console.log("markPrice:", vammState.markPrice);
        _logVAMMState("INITIAL");
    }
    
    function _logVAMMState(string memory description) internal view {
        console.log("--- VIRTUAL AMM STATE:", description, "---");
        console.log("Virtual Base Reserve:", vammState.virtualBase / 1e18, "vETH");
        console.log("Virtual Quote Reserve:", vammState.virtualQuote / 1e6, "USDC");
        console.log("K Constant:", vammState.k / 1e18);
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
    
    function _updateVAMMForTrade(int256 sizeDelta, bool isLong) internal {
        uint256 absSize = uint256(sizeDelta > 0 ? sizeDelta : -sizeDelta);
        
        if (isLong) {
            // Long position: Remove base, add quote (price goes up)
            vammState.totalLongOI += absSize;
            // For simplicity, just add the USD value in USDC units
            uint256 usdValue = (absSize / 1e18) * (vammState.markPrice / 1e18);
            
            // Prevent underflow
            require(vammState.virtualBase >= absSize, "Insufficient virtual base");
            vammState.virtualBase -= absSize;
            vammState.virtualQuote += usdValue * 1e6; // Convert to USDC units
        } else {
            // Short position: Add base, remove quote (price goes down)
            vammState.totalShortOI += absSize;
            uint256 usdValue = (absSize / 1e18) * (vammState.markPrice / 1e18);
            
            // Prevent underflow
            uint256 quoteToRemove = usdValue * 1e6;
            require(vammState.virtualQuote >= quoteToRemove, "Insufficient virtual quote");
            vammState.virtualBase += absSize;
            vammState.virtualQuote -= quoteToRemove;
        }
        
        // Update mark price using simple division
        if (vammState.virtualBase > 0 && vammState.virtualQuote > 0) {
            // Calculate price as USDC per ETH
            // virtualQuote is in 1e6, virtualBase is in 1e18
            // We want result in 1e18 (wei units)
            uint256 baseInEth = vammState.virtualBase / 1e18;
            uint256 quoteInUsd = vammState.virtualQuote / 1e6;
            if (baseInEth > 0) {
                vammState.markPrice = (quoteInUsd * 1e18) / baseInEth;
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
    
    /*//////////////////////////////////////////////////////////////
                        MAIN DEMONSTRATION TEST
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Main demonstration of leverage trading scenarios
    function test_FinalLeverageDemo() public {
        console.log("=== FINAL LEVERAGE TRADING DEMONSTRATION ===");
        console.log("");
        
        // Show initial states
        _logVAMMState("INITIAL");
        _logUserState(alice, "ALICE INITIAL");
        _logUserState(bob, "BOB INITIAL");
        console.log("");
        
        // SCENARIO 1: Alice trades with 2x leverage
        _testAlice2xLeverage();
        
        // SCENARIO 2: Bob trades with 3x leverage
        _testBob3xLeverage();
        
        // SCENARIO 3: Price movements and PnL
        _testPriceMovementsAndPnL();
        
        // SCENARIO 4: Closing positions
        _testClosingPositions();
        
        // Final summary
        _printFinalSummary();
    }
    
    /// @notice Alice opens a 2x leveraged long ETH position
    function _testAlice2xLeverage() internal {
        console.log("SCENARIO 1: Alice's 2x Leveraged Long ETH Position");
        console.log("============================================");
        
        // Alice wants 2x leverage with $2,000 margin
        // At $2,000 ETH price, she can control $4,000 worth = 2 ETH
        uint256 margin = 2000e6; // $2,000 margin
        int256 ethSize = 2e18; // 2 ETH for 2x leverage
        uint256 entryPrice = INITIAL_ETH_PRICE;
        
        console.log("Alice's Trading Plan:");
        console.log("  Margin: $", margin / 1e6);
        console.log("  Leverage: 2x");
        console.log("  Position Size: 2 ETH");
        console.log("  Entry Price: $", entryPrice / 1e18);
        console.log("  Position Value: $", (uint256(ethSize) * entryPrice) / 1e18 / 1e18);
        console.log("");
        
        // Show vAMM state before trade
        _logVAMMState("BEFORE ALICE TRADE");
        
        // Check Alice's initial balance
        uint256 aliceInitialBalance = marginAccount.getAvailableBalance(alice);
        console.log("Alice's available balance before: $", aliceInitialBalance / 1e6);
        
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
        _updateVAMMForTrade(ethSize, true); // Long position
        
        // Check post-position balance
        uint256 alicePostBalance = marginAccount.getAvailableBalance(alice);
        console.log("Alice's available balance after: $", alicePostBalance / 1e6);
        console.log("Margin locked: $", (aliceInitialBalance - alicePostBalance) / 1e6);
        
        // Show vAMM state after trade
        _logVAMMState("AFTER ALICE TRADE");
        _logUserState(alice, "ALICE AFTER TRADE");
        
        // Display position details
        _displayPositionDetails(alice, aliceTokenId, entryPrice, "Alice's Initial Position");
        console.log("");
    }
    
    /// @notice Bob opens a 3x leveraged short ETH position
    function _testBob3xLeverage() internal {
        console.log("SCENARIO 2: Bob's 3x Leveraged Short ETH Position");
        console.log("===========================================");
        
        // Bob wants 3x leverage short with $3,000 margin
        // At $2,000 ETH price, he can control $9,000 worth = 4.5 ETH short
        uint256 margin = 3000e6; // $3,000 margin
        int256 ethSize = -4500000000000000000; // -4.5 ETH for 3x leverage short
        uint256 entryPrice = vammState.markPrice; // Use current vAMM price
        
        console.log("Bob's Trading Plan:");
        console.log("  Margin: $", margin / 1e6);
        console.log("  Leverage: 3x");
        console.log("  Position Size: -4.5 ETH (SHORT)");
        console.log("  Entry Price: $", entryPrice / 1e18);
        console.log("  Position Value: $", (uint256(-ethSize) * entryPrice) / 1e18 / 1e18);
        console.log("");
        
        // Show vAMM state before trade
        _logVAMMState("BEFORE BOB TRADE");
        
        // Check Bob's initial balance
        uint256 bobInitialBalance = marginAccount.getAvailableBalance(bob);
        console.log("Bob's available balance before: $", bobInitialBalance / 1e6);
        
        // Bob opens position
        vm.prank(bob);
        uint256 bobTokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            ethSize,
            entryPrice,
            margin
        );
        
        console.log("Bob opened position #", bobTokenId);
        
        // Update vAMM state to simulate the trade impact
        _updateVAMMForTrade(ethSize, false); // Short position
        
        // Check post-position balance
        uint256 bobPostBalance = marginAccount.getAvailableBalance(bob);
        console.log("Bob's available balance after: $", bobPostBalance / 1e6);
        console.log("Margin locked: $", (bobInitialBalance - bobPostBalance) / 1e6);
        
        // Show vAMM state after trade
        _logVAMMState("AFTER BOB TRADE");
        _logUserState(bob, "BOB AFTER TRADE");
        
        // Display position details
        _displayPositionDetails(bob, bobTokenId, entryPrice, "Bob's Initial Position");
        console.log("");
    }
    
    /// @notice Demonstrate price movements and PnL calculations
    function _testPriceMovementsAndPnL() internal {
        console.log("SCENARIO 3: Price Movements and PnL Demonstration");
        console.log("===============================================");
        
        // Get all open positions
        uint256[] memory alicePositions = positionManager.getUserPositions(alice);
        uint256[] memory bobPositions = positionManager.getUserPositions(bob);
        
        // Price movement 1: ETH price increases to $2,200 (+10%)
        console.log("\nPRICE MOVEMENT 1: ETH rises to $2,200 (+10%)");
        uint256 newEthPrice = 2200e18;
        
        if (alicePositions.length > 0) {
            _displayPositionDetails(alice, alicePositions[0], newEthPrice, "Alice after ETH +10%");
        }
        if (bobPositions.length > 0) {
            _displayPositionDetails(bob, bobPositions[0], newEthPrice, "Bob after ETH +10%");
        }
        
        // Price movement 2: ETH price drops to $1,800 (-10%)
        console.log("\nPRICE MOVEMENT 2: ETH drops to $1,800 (-10%)");
        newEthPrice = 1800e18;
        
        if (alicePositions.length > 0) {
            _displayPositionDetails(alice, alicePositions[0], newEthPrice, "Alice after ETH -10%");
        }
        if (bobPositions.length > 0) {
            _displayPositionDetails(bob, bobPositions[0], newEthPrice, "Bob after ETH -10%");
        }
        
        console.log("\n");
    }
    
    /// @notice Test closing positions with profits/losses
    function _testClosingPositions() internal {
        console.log("SCENARIO 4: Closing Positions");
        console.log("===========================");
        
        uint256[] memory alicePositions = positionManager.getUserPositions(alice);
        uint256[] memory bobPositions = positionManager.getUserPositions(bob);
        
        // Close Alice's position at profit
        if (alicePositions.length > 0) {
            uint256 exitPrice = 2100e18; // +5% profit
            uint256 aliceBalanceBefore = marginAccount.getAvailableBalance(alice);
            int256 expectedPnl = positionManager.getUnrealizedPnL(alicePositions[0], exitPrice);
            
            console.log("Alice closing position at $2,100 (profit)");
            console.log("Expected PnL: $", uint256(expectedPnl) / 1e18);
            
            vm.prank(alice);
            positionManager.closePosition(alicePositions[0], exitPrice);
            
            uint256 aliceBalanceAfter = marginAccount.getAvailableBalance(alice);
            console.log("Alice balance change: $", (aliceBalanceAfter - aliceBalanceBefore) / 1e6);
        }
        
        // Close Bob's position at loss
        if (bobPositions.length > 0) {
            uint256 exitPrice = 2100e18; // Loss for short position
            uint256 bobBalanceBefore = marginAccount.getAvailableBalance(bob);
            int256 expectedPnl = positionManager.getUnrealizedPnL(bobPositions[0], exitPrice);
            
            console.log("Bob closing position at $2,100 (loss for short)");
            console.log("Expected PnL: -$", uint256(-expectedPnl) / 1e18);
            
            vm.prank(bob);
            positionManager.closePosition(bobPositions[0], exitPrice);
            
            uint256 bobBalanceAfter = marginAccount.getAvailableBalance(bob);
            console.log("Bob balance change: $", (bobBalanceAfter - bobBalanceBefore) / 1e6);
        }
        
        console.log("\n");
    }
    
    /*//////////////////////////////////////////////////////////////
                            UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Display detailed position information
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
        
        console.log(description);
        console.log("  User:", userName);
        console.log("  Position ID:", tokenId);
        console.log("  Size:", _formatSize(position.sizeBase));
        console.log("  Margin: $", position.margin / 1e6);
        console.log("  Entry Price: $", position.entryPrice / 1e18);
        console.log("  Current Price: $", currentPrice / 1e18);
        console.log("  Leverage:", leverage / 1e18);
        console.log("  Leverage decimal:", (leverage % 1e18) / 1e17);
        console.log("  Unrealized PnL:", _formatPnL(pnl));
        
        // Calculate percentage gain/loss
        int256 pnlPercentage = (pnl * 100 * 1e18) / int256(uint256(position.margin) * 1e18);
        console.log("  PnL %:", _formatPercentage(pnlPercentage));
        console.log("--------------------------------------------------");
    }
    
    /// @notice Format position size for display
    function _formatSize(int256 size) internal pure returns (string memory) {
        if (size >= 0) {
            return string(abi.encodePacked("+", _toString(uint256(size) / 1e18), " ETH"));
        } else {
            return string(abi.encodePacked("-", _toString(uint256(-size) / 1e18), " ETH"));
        }
    }
    
    /// @notice Format PnL for display
    function _formatPnL(int256 pnl) internal pure returns (string memory) {
        if (pnl >= 0) {
            return string(abi.encodePacked("+$", _toString(uint256(pnl) / 1e18)));
        } else {
            return string(abi.encodePacked("-$", _toString(uint256(-pnl) / 1e18)));
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
        console.log("FINAL SUMMARY");
        console.log("=============");
        
        // User balances
        console.log("\nFinal User Balances:");
        console.log("Alice available balance: $", marginAccount.getAvailableBalance(alice) / 1e6);
        console.log("Bob available balance: $", marginAccount.getAvailableBalance(bob) / 1e6);
        console.log("Charlie available balance: $", marginAccount.getAvailableBalance(charlie) / 1e6);
        
        // Position counts
        console.log("\nPosition Counts:");
        console.log("Alice positions:", positionManager.getUserPositions(alice).length);
        console.log("Bob positions:", positionManager.getUserPositions(bob).length);
        console.log("Charlie positions:", positionManager.getUserPositions(charlie).length);
        console.log("Total positions:", positionManager.totalSupply());
        
        console.log("\nLEVERAGE DEMONSTRATION COMPLETED SUCCESSFULLY!");
        console.log("=============================================");
    }
    
    /*//////////////////////////////////////////////////////////////
                        ADDITIONAL DEMONSTRATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test different leverage scenarios
    function test_DifferentLeverageScenarios() public {
        console.log("\n=== TESTING DIFFERENT LEVERAGE SCENARIOS ===\n");
        
        // 5x Leverage scenario
        console.log("TESTING 5x LEVERAGE:");
        uint256 margin5x = 1000e6; // $1,000 margin
        int256 size5x = 2500000000000000000; // 2.5 ETH for 5x leverage
        
        vm.prank(charlie);
        uint256 token5x = positionManager.openPosition(
            ETH_USDC_MARKET,
            size5x,
            INITIAL_ETH_PRICE,
            margin5x
        );
        
        _displayPositionDetails(charlie, token5x, INITIAL_ETH_PRICE, "Charlie's 5x Leverage Position");
        
        // Show impact at 5% price movement
        uint256 priceUp5 = 2100e18; // +5%
        _displayPositionDetails(charlie, token5x, priceUp5, "Charlie at +5% price move");
        
        console.log("Notice how 5x leverage amplifies both gains and losses!");
    }
    
    /// @notice Test margin management scenarios
    function test_MarginManagementDemo() public {
        console.log("\n=== MARGIN MANAGEMENT DEMONSTRATION ===\n");
        
        // Alice opens a position
        vm.prank(alice);
        uint256 tokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            1e18, // 1 ETH
            INITIAL_ETH_PRICE,
            1000e6 // $1,000 margin
        );
        
        console.log("Alice opened 1 ETH position with $1,000 margin");
        _displayPositionDetails(alice, tokenId, INITIAL_ETH_PRICE, "Initial Position");
        
        // Add margin to reduce leverage
        console.log("\nAlice adds $500 margin to reduce leverage:");
        vm.prank(alice);
        positionManager.addMargin(tokenId, 500e6);
        
        _displayPositionDetails(alice, tokenId, INITIAL_ETH_PRICE, "After Adding Margin");
        
        // Remove some margin
        console.log("\nAlice removes $200 margin:");
        vm.prank(alice);
        positionManager.removeMargin(tokenId, 200e6);
        
        _displayPositionDetails(alice, tokenId, INITIAL_ETH_PRICE, "After Removing Margin");
    }
}
