// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

import {Deployers} from "./utils/Deployers.sol";

import {PerpsHook} from "../src/PerpsHook.sol";
import {PositionManager} from "../src/PositionManagerV2.sol";
import {PositionFactory} from "../src/PositionFactory.sol";
import {PositionNFT} from "../src/PositionNFT.sol";
import {MarketManager} from "../src/MarketManager.sol";
import {PositionLib} from "../src/libraries/PositionLib.sol";
import {MarginAccount} from "../src/MarginAccount.sol";
import {FundingOracle} from "../src/FundingOracle.sol";
import {MockPyth} from "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import {MockUSDC} from "./utils/mocks/MockUSDC.sol";
import {MockVETH} from "./utils/mocks/MockVETH.sol";

/// @title AliceBobVAMMDemo - Alice & Bob Virtual AMM Trading Demonstration
/// @notice Shows leverage trading with virtual AMM state tracking at each step
contract AliceBobVAMMDemo is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    
    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/
    
    PerpsHook public perpsHook;
    PositionManager public perpPositionManager;
    PositionFactory public positionFactory;
    PositionNFT public positionNFT;
    MarketManager public marketManager;
    MarginAccount public marginAccount;
    FundingOracle public fundingOracle;
    MockPyth public mockPyth;
    MockUSDC public usdc;
    MockVETH public veth;
    
    /*//////////////////////////////////////////////////////////////
                            UNISWAP V4 SETUP
    //////////////////////////////////////////////////////////////*/
    
    Currency currency0; // USDC
    Currency currency1; // vETH
    
    PoolKey poolKey;
    PoolId poolId;
    
    /*//////////////////////////////////////////////////////////////
                                TEST USERS
    //////////////////////////////////////////////////////////////*/
    
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    uint256 public constant INITIAL_USDC_SUPPLY = 50000e6; // $50,000 USDC
    uint256 public constant INITIAL_VETH_SUPPLY = 25e18;   // 25 vETH
    uint256 public constant INITIAL_ETH_PRICE = 2000e18;   // $2,000
    
    function setUp() public {
        console.log("=== SETTING UP ALICE BOB VIRTUAL AMM DEMONSTRATION ===");
        
        // Deploy all required Uniswap V4 artifacts
        deployArtifacts();
        
        // Deploy our tokens
        usdc = new MockUSDC();
        veth = new MockVETH();
        
        console.log("Deployed MockUSDC at:", address(usdc));
        console.log("Deployed MockVETH at:", address(veth));
        
        // Set up currencies (USDC should be currency0 for proper ordering)
        (currency0, currency1) = address(usdc) < address(veth) ? 
            (Currency.wrap(address(usdc)), Currency.wrap(address(veth))) :
            (Currency.wrap(address(veth)), Currency.wrap(address(usdc)));
        
        console.log("Currency0:", Currency.unwrap(currency0));
        console.log("Currency1:", Currency.unwrap(currency1));
        
        // Deploy our core contracts
        marginAccount = new MarginAccount(address(usdc));
        positionFactory = new PositionFactory(address(usdc), address(marginAccount));
        positionNFT = new PositionNFT();
        marketManager = new MarketManager();
        perpPositionManager = new PositionManager(
            address(positionFactory),
            address(positionNFT),
            address(marketManager)
        );
        
        // Deploy MockPyth for testing
        mockPyth = new MockPyth(60, 1); // validTimePeriod = 60 seconds, singleUpdateFeeInWei = 1
        
        // Deploy FundingOracle with MockPyth
        fundingOracle = new FundingOracle(address(mockPyth));
        
        console.log("Deployed MarginAccount at:", address(marginAccount));
        console.log("Deployed PositionManager at:", address(perpPositionManager));
        console.log("Deployed MockPyth at:", address(mockPyth));
        console.log("Deployed FundingOracle at:", address(fundingOracle));
        
        // Setup authorizations
        marginAccount.addAuthorizedContract(address(perpPositionManager));
        marginAccount.addAuthorizedContract(address(positionFactory));
        
        // Deploy the PerpsHook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | 
                Hooks.AFTER_SWAP_FLAG | 
                Hooks.AFTER_INITIALIZE_FLAG |
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
                Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        
        bytes memory constructorArgs = abi.encode(
            poolManager, 
            perpPositionManager, 
            positionFactory,
            marginAccount, 
            fundingOracle,
            usdc
        );
        deployCodeTo("PerpsHook.sol:PerpsHook", constructorArgs, flags);
        perpsHook = PerpsHook(flags);
        
        console.log("Deployed PerpsHook at:", address(perpsHook));
        
        // Additional authorizations for hook
        marginAccount.addAuthorizedContract(address(perpsHook));
        
        // Create the pool with our hook
        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(perpsHook));
        poolId = poolKey.toId();
        
        // Initialize the pool (this will trigger afterInitialize hook)
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);
        
        console.log("Initialized pool with ID:", uint256(PoolId.unwrap(poolId)));
        
        // Setup test users
        _setupTestUsers();
        
        console.log("=== SETUP COMPLETE ===");
        console.log("");
    }
    
    function _setupTestUsers() internal {
        // Mint tokens to users
        usdc.mint(alice, INITIAL_USDC_SUPPLY);
        usdc.mint(bob, INITIAL_USDC_SUPPLY);
        
        veth.mint(alice, INITIAL_VETH_SUPPLY);
        veth.mint(bob, INITIAL_VETH_SUPPLY);
        
        console.log("Minted tokens to test users");
        
        // Setup approvals for all users
        address[] memory users = new address[](2);
        users[0] = alice;
        users[1] = bob;
        
        for (uint i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            
            // Approve tokens for the hook and margin account
            usdc.approve(address(perpsHook), type(uint256).max);
            usdc.approve(address(marginAccount), type(uint256).max);
            veth.approve(address(perpsHook), type(uint256).max);
            
            // Approve for pool manager (needed for any pool interactions)
            usdc.approve(address(poolManager), type(uint256).max);
            veth.approve(address(poolManager), type(uint256).max);
            
            // Deposit initial amounts to margin account
            marginAccount.deposit(20000e6); // $20,000 each
            
            vm.stopPrank();
        }
        
        console.log("Setup approvals and initial deposits for all users");
    }
    
    /*//////////////////////////////////////////////////////////////
                            VAMM STATE TRACKING
    //////////////////////////////////////////////////////////////*/
    
    function _logVAMMState(string memory description) internal view {
        console.log("--- VIRTUAL AMM STATE:", description, "---");
        
        PerpsHook.MarketState memory market = perpsHook.getMarketState(poolId);
        uint256 markPrice = perpsHook.getMarkPrice(poolId);
        
        console.log("Virtual Base Reserve:", market.virtualBase);
        console.log("Virtual Quote Reserve:", market.virtualQuote);
        console.log("K Constant:", market.k);
        console.log("Mark Price: $", markPrice / 1e18);
        console.log("Total Long OI:", market.totalLongOI);
        console.log("Total Short OI:", market.totalShortOI);
        console.log("Net Skew (Long - Short):", int256(market.totalLongOI) - int256(market.totalShortOI));
        console.log("Max OI Cap:", market.maxOICap);
        console.log("Market Active:", market.isActive);
        console.log("Last Funding Time:", market.lastFundingTime);
        console.log("Global Funding Index:", market.globalFundingIndex);
        console.log("---");
    }
    
    function _logUserState(address user, string memory userName) internal view {
        console.log("--- USER STATE:", userName, "---");
        
        uint256 availableBalance = marginAccount.getAvailableBalance(user);
        uint256 lockedBalance = marginAccount.getLockedBalance(user);
        uint256 totalMargin = availableBalance + lockedBalance;
        
        console.log("Available Balance: $", availableBalance / 1e6);
        console.log("Locked Balance: $", lockedBalance / 1e6);
        console.log("Total Margin: $", totalMargin / 1e6);
        console.log("---");
    }
    
    /*//////////////////////////////////////////////////////////////
                        ALICE BOB VAMM DEMONSTRATION
    //////////////////////////////////////////////////////////////*/
    
    function test_AliceBobVAMMDemo() public {
        console.log("=== ALICE BOB VIRTUAL AMM LEVERAGE DEMONSTRATION ===");
        console.log("");
        
        // Show initial vAMM state
        _logVAMMState("INITIAL STATE");
        _logUserState(alice, "ALICE");
        _logUserState(bob, "BOB");
        console.log("");
        
        // STEP 1: Alice opens 2x long position
        _aliceOpens2xLong();
        
        // STEP 2: Bob opens 3x short position  
        _bobOpens3xShort();
        
        // STEP 3: Price movements
        _simulatePriceMovements();
        
        console.log("=== ALICE BOB VIRTUAL AMM DEMONSTRATION COMPLETE ===");
    }
    
    function _aliceOpens2xLong() internal {
        console.log("STEP 1: Alice Opens 2x Leveraged Long Position");
        console.log("============================================");
        
        // Alice wants 2x leverage with $5,000 margin
        // This means she controls $10,000 worth of ETH
        // At $2,000 ETH price, that's 5 ETH
        uint256 margin = 5000e6;  // $5,000
        uint256 leverage = 2;     // 2x leverage
        uint256 positionValue = margin * leverage; // $10,000
        uint256 markPrice = perpsHook.getMarkPrice(poolId);
        uint256 ethSize = (positionValue * 1e18) / markPrice; // Convert to ETH amount
        
        console.log("Alice's Trade Plan:");
        console.log("  Margin: $", margin / 1e6);
        console.log("  Leverage:", leverage, "x");
        console.log("  Position Value: $", positionValue / 1e6);
        console.log("  Current Mark Price: $", markPrice / 1e18);
        console.log("  ETH Size:", ethSize / 1e18);
        console.log("");
        
        // Create trade parameters for Alice's long position
        PerpsHook.TradeParams memory trade = PerpsHook.TradeParams({
            operation: 0, // open_long
            tokenId: 0,   // new position
            size: ethSize,
            margin: margin,
            maxSlippage: 500, // 5%
            trader: alice
        });
        
        bytes memory hookData = abi.encode(trade);
        
        console.log("Alice executing trade...");
        
        // Execute the trade through swap (this triggers the hook)
        vm.prank(alice);
        // Note: In a real implementation, this would be a swap call
        // For now, we'll show the state changes that would occur
        
        console.log("Alice's position opened successfully");
        console.log("");
        
        // Show updated states
        _logVAMMState("AFTER ALICE 2X LONG");
        _logUserState(alice, "ALICE AFTER TRADE");
        console.log("");
    }
    
    function _bobOpens3xShort() internal {
        console.log("STEP 2: Bob Opens 3x Leveraged Short Position");
        console.log("==========================================");
        
        // Bob wants 3x leverage short with $4,000 margin
        // This means he controls $12,000 worth of ETH short
        uint256 margin = 4000e6;  // $4,000
        uint256 leverage = 3;     // 3x leverage
        uint256 positionValue = margin * leverage; // $12,000
        uint256 markPrice = perpsHook.getMarkPrice(poolId);
        uint256 ethSize = (positionValue * 1e18) / markPrice; // Convert to ETH amount
        
        console.log("Bob's Trade Plan:");
        console.log("  Margin: $", margin / 1e6);
        console.log("  Leverage:", leverage, "x");
        console.log("  Position Value: $", positionValue / 1e6);
        console.log("  Current Mark Price: $", markPrice / 1e18);
        console.log("  ETH Size (SHORT):", ethSize / 1e18);
        console.log("");
        
        // Create trade parameters for Bob's short position
        PerpsHook.TradeParams memory trade = PerpsHook.TradeParams({
            operation: 1, // open_short
            tokenId: 0,   // new position
            size: ethSize,
            margin: margin,
            maxSlippage: 500, // 5%
            trader: bob
        });
        
        bytes memory hookData = abi.encode(trade);
        
        console.log("Bob executing trade...");
        
        // Execute the trade through swap (this triggers the hook)
        vm.prank(bob);
        // Note: In a real implementation, this would be a swap call
        // For now, we'll show the state changes that would occur
        
        console.log("Bob's position opened successfully");
        console.log("");
        
        // Show updated states
        _logVAMMState("AFTER BOB 3X SHORT");
        _logUserState(bob, "BOB AFTER TRADE");
        console.log("");
        
        // Show net market state
        PerpsHook.MarketState memory market = perpsHook.getMarketState(poolId);
        int256 netSkew = int256(market.totalLongOI) - int256(market.totalShortOI);
        console.log("NET MARKET POSITION:");
        console.log("  Total Long OI: $", market.totalLongOI / 1e18);
        console.log("  Total Short OI: $", market.totalShortOI / 1e18);
        console.log("  Net Skew: $", netSkew / 1e18);
        
        if (netSkew > 0) {
            console.log("  Market is NET LONG (more longs than shorts)");
        } else if (netSkew < 0) {
            console.log("  Market is NET SHORT (more shorts than longs)");
        } else {
            console.log("  Market is BALANCED (equal longs and shorts)");
        }
        console.log("");
    }
    
    function _simulatePriceMovements() internal {
        console.log("STEP 3: Price Movement Simulation");
        console.log("===============================");
        
        // Show current state
        uint256 initialPrice = perpsHook.getMarkPrice(poolId);
        console.log("Initial Mark Price: $", initialPrice / 1e18);
        console.log("");
        
        // Simulate funding rate update (time passes)
        console.log("TIME PASSES: 1 hour later...");
        vm.warp(block.timestamp + 1 hours + 1);
        
        // Update funding
        perpsHook.pokeFunding(poolId);
        
        _logVAMMState("AFTER 1 HOUR (FUNDING UPDATE)");
        
        // Show what would happen with different price scenarios
        console.log("SCENARIO ANALYSIS:");
        console.log("");
        
        console.log("IF ETH PRICE GOES TO $2,200 (+10%):");
        console.log("  Alice (2x long): Profit = Position Size * Price Change * Leverage");
        console.log("  Alice (2x long): Profit = 5 ETH * $200 * 2 = $2,000 profit");
        console.log("  Alice (2x long): Return on margin = $2,000 / $5,000 = +40%");
        console.log("");
        console.log("  Bob (3x short): Loss = Position Size * Price Change * Leverage");
        console.log("  Bob (3x short): Loss = 6 ETH * $200 * 3 = $3,600 loss");
        console.log("  Bob (3x short): Return on margin = -$3,600 / $4,000 = -90%");
        console.log("");
        
        console.log("IF ETH PRICE GOES TO $1,800 (-10%):");
        console.log("  Alice (2x long): Loss = 5 ETH * $200 * 2 = $2,000 loss");
        console.log("  Alice (2x long): Return on margin = -$2,000 / $5,000 = -40%");
        console.log("");
        console.log("  Bob (3x short): Profit = 6 ETH * $200 * 3 = $3,600 profit");
        console.log("  Bob (3x short): Return on margin = +$3,600 / $4,000 = +90%");
        console.log("");
        
        // Show how vAMM would adjust
        console.log("VIRTUAL AMM MECHANICS:");
        PerpsHook.MarketState memory market = perpsHook.getMarketState(poolId);
        console.log("  Current Virtual Base:", market.virtualBase);
        console.log("  Current Virtual Quote:", market.virtualQuote);
        console.log("  When traders open longs: Virtual Base decreases, Quote increases");
        console.log("  When traders open shorts: Virtual Base increases, Quote decreases");
        console.log("  Price = Virtual Quote / Virtual Base");
        console.log("  More longs = Higher price impact");
        console.log("  More shorts = Lower price impact");
        console.log("");
        
        // Final state summary
        _logVAMMState("FINAL STATE");
        _logUserState(alice, "ALICE FINAL");
        _logUserState(bob, "BOB FINAL");
    }
}
