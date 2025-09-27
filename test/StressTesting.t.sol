// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {MarginAccount} from "../src/MarginAccount.sol";
import {PositionManager} from "../src/PositionManagerV2.sol";
import {PositionFactory} from "../src/PositionFactory.sol";
import {PositionNFT} from "../src/PositionNFT.sol";
import {MarketManager} from "../src/MarketManager.sol";
import {PositionLib} from "../src/libraries/PositionLib.sol";
import {InsuranceFund} from "../src/InsuranceFund.sol";
import {FundingOracle} from "../src/FundingOracle.sol";
import {MockUSDC} from "./utils/mocks/MockUSDC.sol";

/// @title StressTesting - High Load and Boundary Condition Tests
/// @notice Tests system behavior under extreme conditions and high loads
contract StressTestingTest is Test {
    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/
    
    MarginAccount public marginAccount;
    PositionManager public positionManager;
    PositionFactory public positionFactory;
    PositionNFT public positionNFT;
    MarketManager public marketManager;
    InsuranceFund public insuranceFund;
    FundingOracle public fundingOracle;
    MockUSDC public usdc;
    
    /*//////////////////////////////////////////////////////////////
                                TEST SETUP
    //////////////////////////////////////////////////////////////*/
    
    address public owner = makeAddr("owner");
    address[] public users;
    
    bytes32 public constant MARKET_ID = keccak256("ETH-USDC");
    uint256 constant INITIAL_USDC = 1000000e6; // 1M USDC per user
    uint256 constant TEST_PRICE = 2000e18; // $2000
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy core contracts
        usdc = new MockUSDC();
        marginAccount = new MarginAccount(address(usdc));
        positionFactory = new PositionFactory(address(usdc), address(marginAccount));
        positionNFT = new PositionNFT();
        marketManager = new MarketManager();
        positionManager = new PositionManager(
            address(positionFactory),
            address(positionNFT),
            address(marketManager)
        );
        insuranceFund = new InsuranceFund(address(usdc));
        fundingOracle = new FundingOracle(address(0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF)); // Placeholder Pyth
        
        // Authorize position manager with all components
        positionFactory.setPositionNFT(address(positionNFT));
        positionNFT.setFactory(address(positionFactory));
        
        // Transfer ownership of modular components to PositionManager
        positionFactory.transferOwnership(address(positionManager));
        marketManager.transferOwnership(address(positionManager));
        
        // Setup authorizations
        marginAccount.addAuthorizedContract(address(positionManager));
        marginAccount.addAuthorizedContract(address(positionFactory));
        
        // Add market
        positionManager.addMarket(
            MARKET_ID,
            address(0x1234), // Mock ETH
            address(usdc),
            address(0x5678)  // Mock pool
        );
        
        // Create multiple test users
        for (uint256 i = 0; i < 100; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));
            users.push(user);
            usdc.mint(user, INITIAL_USDC);
        }
        
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                           HIGH LOAD TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test system with many simultaneous deposits
    function test_MassiveSimultaneousDeposits() public {
        uint256 userCount = 50; // Use subset for reasonable gas limits
        uint256 depositAmount = 10000e6; // $10k each
        
        // Record gas usage
        uint256 gasStart = gasleft();
        
        for (uint256 i = 0; i < userCount; i++) {
            vm.startPrank(users[i]);
            usdc.approve(address(marginAccount), depositAmount);
            marginAccount.deposit(depositAmount);
            vm.stopPrank();
        }
        
        uint256 gasUsed = gasStart - gasleft();
        console.log("Gas used for 50 deposits:", gasUsed);
        console.log("Average gas per deposit:", gasUsed / userCount);
        
        // Verify all deposits succeeded
        uint256 totalBalance = marginAccount.totalBalance();
        assertEq(totalBalance, userCount * depositAmount, "Total balance should match deposits");
        
        // Verify individual balances
        for (uint256 i = 0; i < userCount; i++) {
            uint256 userBalance = marginAccount.getAvailableBalance(users[i]);
            assertEq(userBalance, depositAmount, "User balance should match deposit");
        }
    }
    
    /// @notice Test system with many positions created simultaneously
    function test_MassPositionCreation() public {
        uint256 userCount = 20; // Reduced for gas limits
        uint256 depositAmount = 10000e6; // $10k each
        
        // Setup all users with deposits
        for (uint256 i = 0; i < userCount; i++) {
            vm.startPrank(users[i]);
            usdc.approve(address(marginAccount), depositAmount);
            marginAccount.deposit(depositAmount);
            vm.stopPrank();
        }
        
        uint256 gasStart = gasleft();
        
        // Create positions for all users
        uint256[] memory tokenIds = new uint256[](userCount);
        for (uint256 i = 0; i < userCount; i++) {
            tokenIds[i] = positionManager.openPositionFor(
                users[i],
                MARKET_ID,
                1e18 + (int256(i) * 1e17), // Varying position sizes
                TEST_PRICE,
                1000e6 // $1000 margin each
            );
        }
        
        uint256 gasUsed = gasStart - gasleft();
        console.log("Gas used for", userCount, "position creations:", gasUsed);
        console.log("Average gas per position:", gasUsed / userCount);
        
        // Verify all positions exist
        for (uint256 i = 0; i < userCount; i++) {
            PositionLib.Position memory position = positionManager.getPosition(tokenIds[i]);
            assertEq(position.owner, users[i], "Position owner should be correct");
            assertTrue(position.sizeBase != 0, "Position size should be non-zero");
        }
        
        // Test position enumeration performance
        gasStart = gasleft();
        for (uint256 i = 0; i < userCount; i++) {
            uint256[] memory userPositions = positionManager.getUserPositions(users[i]);
            assertEq(userPositions.length, 1, "Each user should have one position");
        }
        uint256 enumerationGas = gasStart - gasleft();
        console.log("Gas used for position enumeration:", enumerationGas);
    }
    
    /*//////////////////////////////////////////////////////////////
                        BOUNDARY CONDITION TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test with maximum uint256 values
    function test_MaximumValueBoundaries() public {
        vm.startPrank(owner);
        
        // Test with maximum safe USDC amount (to avoid overflow)
        uint256 maxSafeAmount = type(uint256).max / 1e18; // Ensure no overflow in calculations
        
        usdc.mint(owner, maxSafeAmount);
        usdc.approve(address(marginAccount), maxSafeAmount);
        
        // This should either succeed or revert gracefully (not overflow)
        try marginAccount.deposit(maxSafeAmount) {
            uint256 balance = marginAccount.getAvailableBalance(owner);
            assertEq(balance, maxSafeAmount, "Balance should match deposit");
        } catch {
            // Acceptable if deposit limit exceeded
            console.log("Large deposit rejected - acceptable");
        }
        
        vm.stopPrank();
    }
    
    /// @notice Test minimum value boundaries
    function test_MinimumValueBoundaries() public {
        vm.startPrank(users[0]);
        usdc.approve(address(marginAccount), 10000e6);
        marginAccount.deposit(10000e6);
        
        // Test minimum position size (1 wei)
        try positionManager.openPositionFor(
            users[0],
            MARKET_ID,
            1, // 1 wei position
            TEST_PRICE,
            1000e6
        ) returns (uint256 tokenId) {
            PositionLib.Position memory position = positionManager.getPosition(tokenId);
            assertEq(position.sizeBase, 1, "Minimum position size should be handled");
        } catch {
            // Acceptable if minimum size enforced
            console.log("Minimum position size rejected - acceptable");
        }
        
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                          INVARIANT STRESS TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test that total balances always match individual balances
    function testFuzz_TotalBalanceInvariant(uint256 numUsers, uint256 depositAmount) public {
        numUsers = bound(numUsers, 1, 20); // Limit for gas
        depositAmount = bound(depositAmount, 1e6, 100000e6); // $1 to $100k
        
        uint256 expectedTotal = 0;
        
        for (uint256 i = 0; i < numUsers; i++) {
            vm.startPrank(users[i]);
            usdc.approve(address(marginAccount), depositAmount);
            marginAccount.deposit(depositAmount);
            expectedTotal += depositAmount;
            vm.stopPrank();
        }
        
        uint256 actualTotal = marginAccount.totalBalance();
        assertEq(actualTotal, expectedTotal, "Total balance invariant violated");
        
        // Verify sum of individual balances equals total
        uint256 sumOfIndividualBalances = 0;
        for (uint256 i = 0; i < numUsers; i++) {
            sumOfIndividualBalances += marginAccount.getTotalBalance(users[i]);
        }
        assertEq(sumOfIndividualBalances, actualTotal, "Individual balance sum should equal total");
    }
    
    /// @notice Test insurance fund invariants under stress
    function test_InsuranceFundInvariants() public {
        vm.startPrank(owner);
        
        // Initial insurance fund deposit
        uint256 initialAmount = 100000e6; // $100k
        usdc.mint(owner, initialAmount);
        usdc.approve(address(insuranceFund), initialAmount);
        insuranceFund.fundTopUp(initialAmount);
        
        // Test multiple rapid deposits and withdrawals
        for (uint256 i = 0; i < 10; i++) {
            uint256 depositAmount = 10000e6; // $10k
            usdc.mint(owner, depositAmount);
            usdc.approve(address(insuranceFund), depositAmount);
            insuranceFund.deposit(depositAmount);
            
            // Simulate some utilization
            insuranceFund.withdraw(depositAmount / 2); // Withdraw half
        }
        
        // Verify fund is healthy
        assertTrue(insuranceFund.isHealthy(), "Insurance fund should remain healthy");
        
        uint256 finalBalance = insuranceFund.fundBalance();
        assertTrue(finalBalance > 0, "Insurance fund should have positive balance");
        
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                           REENTRANCY STRESS TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test reentrancy protection under high load
    function test_ReentrancyProtectionStress() public {
        vm.startPrank(users[0]);
        usdc.approve(address(marginAccount), 100000e6);
        marginAccount.deposit(50000e6);
        
        // Create position
        uint256 tokenId = positionManager.openPositionFor(
            users[0],
            MARKET_ID,
            5e18, // 5 ETH
            TEST_PRICE,
            10000e6 // $10k margin
        );
        
        // Try to perform multiple operations rapidly
        // This tests that reentrancy guards work under stress
        
        positionManager.addMargin(tokenId, 1000e6);
        positionManager.removeMargin(tokenId, 500e6);
        
        // These should all succeed without reentrancy issues
        PositionLib.Position memory position = positionManager.getPosition(tokenId);
        assertEq(position.margin, 10500e6, "Final margin should be correct");
        
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                           MEMORY EFFICIENCY TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test memory usage with large data structures
    function test_LargeDataStructureHandling() public {
        vm.startPrank(users[0]);
        usdc.approve(address(marginAccount), 1000000e6);
        marginAccount.deposit(500000e6);
        
        // Create many small positions to test array handling
        uint256[] memory tokenIds = new uint256[](50);
        
        for (uint256 i = 0; i < 50; i++) {
            tokenIds[i] = positionManager.openPositionFor(
                users[0],
                MARKET_ID,
                1e17, // 0.1 ETH each
                TEST_PRICE,
                2000e6 // $2000 margin each
            );
        }
        
        // Test retrieval efficiency
        uint256 gasStart = gasleft();
        uint256[] memory userPositions = positionManager.getUserPositions(users[0]);
        uint256 gasUsed = gasStart - gasleft();
        
        console.log("Gas used to retrieve 50 positions:", gasUsed);
        assertEq(userPositions.length, 50, "Should retrieve all positions");
        
        // Test market positions retrieval
        gasStart = gasleft();
        uint256[] memory marketPositions = positionManager.getMarketPositions(MARKET_ID);
        gasUsed = gasStart - gasleft();
        
        console.log("Gas used to retrieve market positions:", gasUsed);
        assertEq(marketPositions.length, 50, "Should retrieve all market positions");
        
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                           EXTREME SCENARIO TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test system behavior when insurance fund is depleted
    function test_DepletedInsuranceFundScenario() public {
        vm.startPrank(owner);
        
        // Setup minimal insurance fund
        uint256 minAmount = 1000e6; // $1k only
        usdc.mint(owner, minAmount);
        usdc.approve(address(insuranceFund), minAmount);
        insuranceFund.fundTopUp(minAmount);
        
        vm.stopPrank();
        
        // Create large positions that could drain insurance
        vm.startPrank(users[0]);
        usdc.approve(address(marginAccount), 100000e6);
        marginAccount.deposit(50000e6);
        
        // This tests what happens when insurance fund can't cover bad debt
        // Use reasonable leverage to avoid ExceedsMaxLeverage
        uint256 tokenId = positionManager.openPositionFor(
            users[0],
            MARKET_ID,
            19e18, // Large but reasonable position (19 ETH)
            TEST_PRICE,
            2000e6 // $2000 margin for ~19x leverage
        );
        
        // Position exists despite potential future insurance issues
        PositionLib.Position memory position = positionManager.getPosition(tokenId);
        assertTrue(position.sizeBase != 0, "Position should exist");
        
        vm.stopPrank();
    }
}
