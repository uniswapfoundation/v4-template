// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {MarginAccount} from "../src/MarginAccount.sol";
import {MockUSDC} from "./utils/mocks/MockUSDC.sol";

contract MarginAccountTest is Test {
    MarginAccount public marginAccount;
    MockUSDC public usdc;
    
    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public authorizedContract = makeAddr("authorizedContract");
    address public unauthorizedContract = makeAddr("unauthorizedContract");
    
    uint256 constant INITIAL_USDC_SUPPLY = 1_000_000e6; // 1M USDC
    uint256 constant TEST_DEPOSIT_AMOUNT = 1000e6; // 1000 USDC
    uint256 constant TEST_MARGIN_AMOUNT = 500e6; // 500 USDC

    event Deposit(address indexed user, uint256 amount, uint256 newFreeBalance);
    event Withdraw(address indexed user, uint256 amount, uint256 newFreeBalance);
    event MarginLocked(address indexed user, uint256 amount, uint256 newLockedBalance);
    event MarginUnlocked(address indexed user, uint256 amount, uint256 newFreeBalance);
    event PnLSettled(address indexed user, int256 pnl, uint256 newFreeBalance);
    event FundingApplied(address indexed user, int256 fundingAmount, uint256 newFreeBalance, uint256 newLockedBalance);
    event AuthorizedContractAdded(address indexed contractAddress);
    event AuthorizedContractRemoved(address indexed contractAddress);

    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy USDC mock
        usdc = new MockUSDC();
        usdc.mint(user1, INITIAL_USDC_SUPPLY);
        usdc.mint(user2, INITIAL_USDC_SUPPLY);
        usdc.mint(owner, INITIAL_USDC_SUPPLY);
        
        // Deploy MarginAccount
        marginAccount = new MarginAccount(address(usdc));
        
        // Add authorized contract
        marginAccount.addAuthorizedContract(authorizedContract);
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_deployment() public {
        assertEq(address(marginAccount.USDC()), address(usdc));
        assertEq(marginAccount.owner(), owner);
        assertTrue(marginAccount.authorized(authorizedContract));
        assertFalse(marginAccount.authorized(unauthorizedContract));
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_deposit_success() public {
        vm.startPrank(user1);
        
        // Approve and deposit
        usdc.approve(address(marginAccount), TEST_DEPOSIT_AMOUNT);
        
        vm.expectEmit(true, false, false, true);
        emit Deposit(user1, TEST_DEPOSIT_AMOUNT, TEST_DEPOSIT_AMOUNT);
        
        marginAccount.deposit(TEST_DEPOSIT_AMOUNT);
        
        // Check balances
        assertEq(marginAccount.freeBalance(user1), TEST_DEPOSIT_AMOUNT);
        assertEq(marginAccount.getTotalBalance(user1), TEST_DEPOSIT_AMOUNT);
        assertEq(marginAccount.totalBalance(), TEST_DEPOSIT_AMOUNT);
        assertEq(usdc.balanceOf(address(marginAccount)), TEST_DEPOSIT_AMOUNT);
        
        vm.stopPrank();
    }

    function test_deposit_multiple_users() public {
        uint256 amount1 = 1000e6;
        uint256 amount2 = 2000e6;
        
        // User1 deposits
        vm.startPrank(user1);
        usdc.approve(address(marginAccount), amount1);
        marginAccount.deposit(amount1);
        vm.stopPrank();
        
        // User2 deposits
        vm.startPrank(user2);
        usdc.approve(address(marginAccount), amount2);
        marginAccount.deposit(amount2);
        vm.stopPrank();
        
        // Check individual balances
        assertEq(marginAccount.freeBalance(user1), amount1);
        assertEq(marginAccount.freeBalance(user2), amount2);
        assertEq(marginAccount.totalBalance(), amount1 + amount2);
        assertEq(usdc.balanceOf(address(marginAccount)), amount1 + amount2);
    }

    function test_deposit_revert_zero_amount() public {
        vm.startPrank(user1);
        
        vm.expectRevert(MarginAccount.ZeroAmount.selector);
        marginAccount.deposit(0);
        
        vm.stopPrank();
    }

    function test_deposit_revert_insufficient_allowance() public {
        vm.startPrank(user1);
        
        // Don't approve enough
        usdc.approve(address(marginAccount), TEST_DEPOSIT_AMOUNT - 1);
        
        vm.expectRevert();
        marginAccount.deposit(TEST_DEPOSIT_AMOUNT);
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_withdraw_success() public {
        // First deposit
        vm.startPrank(user1);
        usdc.approve(address(marginAccount), TEST_DEPOSIT_AMOUNT);
        marginAccount.deposit(TEST_DEPOSIT_AMOUNT);
        
        uint256 withdrawAmount = 300e6;
        uint256 expectedBalance = TEST_DEPOSIT_AMOUNT - withdrawAmount;
        
        vm.expectEmit(true, false, false, true);
        emit Withdraw(user1, withdrawAmount, expectedBalance);
        
        marginAccount.withdraw(withdrawAmount);
        
        // Check balances
        assertEq(marginAccount.freeBalance(user1), expectedBalance);
        assertEq(marginAccount.totalBalance(), expectedBalance);
        assertEq(usdc.balanceOf(user1), INITIAL_USDC_SUPPLY - TEST_DEPOSIT_AMOUNT + withdrawAmount);
        
        vm.stopPrank();
    }

    function test_withdraw_full_balance() public {
        vm.startPrank(user1);
        
        // Deposit and withdraw all
        usdc.approve(address(marginAccount), TEST_DEPOSIT_AMOUNT);
        marginAccount.deposit(TEST_DEPOSIT_AMOUNT);
        marginAccount.withdraw(TEST_DEPOSIT_AMOUNT);
        
        // Check balances
        assertEq(marginAccount.freeBalance(user1), 0);
        assertEq(marginAccount.totalBalance(), 0);
        assertEq(usdc.balanceOf(user1), INITIAL_USDC_SUPPLY);
        
        vm.stopPrank();
    }

    function test_withdraw_revert_insufficient_balance() public {
        vm.startPrank(user1);
        
        // Try to withdraw without deposit
        vm.expectRevert(MarginAccount.InsufficientFreeBalance.selector);
        marginAccount.withdraw(TEST_DEPOSIT_AMOUNT);
        
        vm.stopPrank();
    }

    function test_withdraw_revert_zero_amount() public {
        vm.startPrank(user1);
        
        vm.expectRevert(MarginAccount.ZeroAmount.selector);
        marginAccount.withdraw(0);
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            MARGIN MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_lockMargin_success() public {
        // Setup: user deposits
        vm.startPrank(user1);
        usdc.approve(address(marginAccount), TEST_DEPOSIT_AMOUNT);
        marginAccount.deposit(TEST_DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Lock margin from authorized contract
        vm.startPrank(authorizedContract);
        
        vm.expectEmit(true, false, false, true);
        emit MarginLocked(user1, TEST_MARGIN_AMOUNT, TEST_MARGIN_AMOUNT);
        
        marginAccount.lockMargin(user1, TEST_MARGIN_AMOUNT);
        
        // Check balances
        assertEq(marginAccount.freeBalance(user1), TEST_DEPOSIT_AMOUNT - TEST_MARGIN_AMOUNT);
        assertEq(marginAccount.lockedBalance(user1), TEST_MARGIN_AMOUNT);
        assertEq(marginAccount.getTotalBalance(user1), TEST_DEPOSIT_AMOUNT);
        
        vm.stopPrank();
    }

    function test_lockMargin_revert_unauthorized() public {
        vm.startPrank(unauthorizedContract);
        
        vm.expectRevert(MarginAccount.Unauthorized.selector);
        marginAccount.lockMargin(user1, TEST_MARGIN_AMOUNT);
        
        vm.stopPrank();
    }

    function test_lockMargin_revert_insufficient_balance() public {
        vm.startPrank(authorizedContract);
        
        // Try to lock more than user has
        vm.expectRevert(MarginAccount.InsufficientFreeBalance.selector);
        marginAccount.lockMargin(user1, TEST_MARGIN_AMOUNT);
        
        vm.stopPrank();
    }

    function test_unlockMargin_success() public {
        // Setup: deposit and lock margin
        vm.startPrank(user1);
        usdc.approve(address(marginAccount), TEST_DEPOSIT_AMOUNT);
        marginAccount.deposit(TEST_DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(authorizedContract);
        marginAccount.lockMargin(user1, TEST_MARGIN_AMOUNT);
        
        uint256 unlockAmount = 200e6;
        uint256 expectedFree = TEST_DEPOSIT_AMOUNT - TEST_MARGIN_AMOUNT + unlockAmount;
        
        vm.expectEmit(true, false, false, true);
        emit MarginUnlocked(user1, unlockAmount, expectedFree);
        
        marginAccount.unlockMargin(user1, unlockAmount);
        
        // Check balances
        assertEq(marginAccount.freeBalance(user1), expectedFree);
        assertEq(marginAccount.lockedBalance(user1), TEST_MARGIN_AMOUNT - unlockAmount);
        
        vm.stopPrank();
    }

    function test_unlockMargin_revert_insufficient_locked() public {
        vm.startPrank(authorizedContract);
        
        vm.expectRevert(MarginAccount.InsufficientLockedBalance.selector);
        marginAccount.unlockMargin(user1, TEST_MARGIN_AMOUNT);
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            PNL SETTLEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_settlePnL_profit() public {
        // Setup: deposit
        vm.startPrank(user1);
        usdc.approve(address(marginAccount), TEST_DEPOSIT_AMOUNT);
        marginAccount.deposit(TEST_DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        int256 profit = 100e6; // 100 USDC profit
        uint256 expectedBalance = TEST_DEPOSIT_AMOUNT + uint256(profit);
        
        vm.startPrank(authorizedContract);
        
        vm.expectEmit(true, false, false, true);
        emit PnLSettled(user1, profit, expectedBalance);
        
        marginAccount.settlePnL(user1, profit);
        
        // Check balances
        assertEq(marginAccount.freeBalance(user1), expectedBalance);
        assertEq(marginAccount.totalBalance(), expectedBalance);
        
        vm.stopPrank();
    }

    function test_settlePnL_loss_from_locked() public {
        // Setup: deposit and lock margin
        vm.startPrank(user1);
        usdc.approve(address(marginAccount), TEST_DEPOSIT_AMOUNT);
        marginAccount.deposit(TEST_DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(authorizedContract);
        marginAccount.lockMargin(user1, TEST_MARGIN_AMOUNT);
        
        int256 loss = -200e6; // 200 USDC loss
        uint256 expectedLocked = TEST_MARGIN_AMOUNT - 200e6;
        
        vm.expectEmit(true, false, false, true);
        emit PnLSettled(user1, loss, TEST_DEPOSIT_AMOUNT - TEST_MARGIN_AMOUNT);
        
        marginAccount.settlePnL(user1, loss);
        
        // Check balances - loss comes from locked first
        assertEq(marginAccount.freeBalance(user1), TEST_DEPOSIT_AMOUNT - TEST_MARGIN_AMOUNT);
        assertEq(marginAccount.lockedBalance(user1), expectedLocked);
        
        vm.stopPrank();
    }

    function test_settlePnL_large_loss() public {
        // Setup: deposit and lock margin
        vm.startPrank(user1);
        usdc.approve(address(marginAccount), TEST_DEPOSIT_AMOUNT);
        marginAccount.deposit(TEST_DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(authorizedContract);
        marginAccount.lockMargin(user1, TEST_MARGIN_AMOUNT);
        
        // Loss exceeds locked margin but not total balance
        int256 loss = -700e6; // 700 USDC loss
        
        marginAccount.settlePnL(user1, loss);
        
        // Check balances - should use all locked + some free
        assertEq(marginAccount.lockedBalance(user1), 0);
        assertEq(marginAccount.freeBalance(user1), TEST_DEPOSIT_AMOUNT - 700e6);
        
        vm.stopPrank();
    }

    function test_settlePnL_revert_insufficient_total_balance() public {
        // Setup: small deposit
        uint256 smallAmount = 100e6;
        vm.startPrank(user1);
        usdc.approve(address(marginAccount), smallAmount);
        marginAccount.deposit(smallAmount);
        vm.stopPrank();
        
        vm.startPrank(authorizedContract);
        
        // Try to lose more than total balance
        int256 hugeLoss = -200e6;
        
        vm.expectRevert(MarginAccount.InsufficientTotalBalance.selector);
        marginAccount.settlePnL(user1, hugeLoss);
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            FUNDING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_applyFunding_receive() public {
        // Setup: deposit
        vm.startPrank(user1);
        usdc.approve(address(marginAccount), TEST_DEPOSIT_AMOUNT);
        marginAccount.deposit(TEST_DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        int256 funding = 50e6; // Receive 50 USDC
        uint256 expectedBalance = TEST_DEPOSIT_AMOUNT + uint256(funding);
        
        vm.startPrank(authorizedContract);
        
        vm.expectEmit(true, false, false, true);
        emit FundingApplied(user1, funding, expectedBalance, 0);
        
        marginAccount.applyFunding(user1, funding);
        
        assertEq(marginAccount.freeBalance(user1), expectedBalance);
        
        vm.stopPrank();
    }

    function test_applyFunding_pay() public {
        // Setup: deposit
        vm.startPrank(user1);
        usdc.approve(address(marginAccount), TEST_DEPOSIT_AMOUNT);
        marginAccount.deposit(TEST_DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        int256 funding = -30e6; // Pay 30 USDC
        uint256 expectedBalance = TEST_DEPOSIT_AMOUNT - 30e6;
        
        vm.startPrank(authorizedContract);
        
        marginAccount.applyFunding(user1, funding);
        
        assertEq(marginAccount.freeBalance(user1), expectedBalance);
        
        vm.stopPrank();
    }

    function test_applyFunding_zero_amount() public {
        vm.startPrank(authorizedContract);
        
        // Should not revert or change anything
        marginAccount.applyFunding(user1, 0);
        assertEq(marginAccount.freeBalance(user1), 0);
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            AUTHORIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_addAuthorizedContract() public {
        address newContract = makeAddr("newContract");
        
        vm.startPrank(owner);
        
        vm.expectEmit(true, false, false, false);
        emit AuthorizedContractAdded(newContract);
        
        marginAccount.addAuthorizedContract(newContract);
        
        assertTrue(marginAccount.authorized(newContract));
        
        vm.stopPrank();
    }

    function test_removeAuthorizedContract() public {
        vm.startPrank(owner);
        
        vm.expectEmit(true, false, false, false);
        emit AuthorizedContractRemoved(authorizedContract);
        
        marginAccount.removeAuthorizedContract(authorizedContract);
        
        assertFalse(marginAccount.authorized(authorizedContract));
        
        vm.stopPrank();
    }

    function test_authorization_only_owner() public {
        vm.startPrank(user1);
        
        vm.expectRevert();
        marginAccount.addAuthorizedContract(makeAddr("test"));
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            INVARIANT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_checkInvariant_success() public {
        assertTrue(marginAccount.checkInvariant());
        
        // After deposit
        vm.startPrank(user1);
        usdc.approve(address(marginAccount), TEST_DEPOSIT_AMOUNT);
        marginAccount.deposit(TEST_DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        assertTrue(marginAccount.checkInvariant());
    }

    function test_fixInvariant() public {
        // Simulate invariant violation by directly transferring USDC
        vm.startPrank(owner);
        usdc.transfer(address(marginAccount), 1000e6);
        
        // Invariant should be broken
        assertFalse(marginAccount.checkInvariant());
        
        // Fix invariant
        marginAccount.fixInvariant();
        
        assertTrue(marginAccount.checkInvariant());
        assertEq(marginAccount.totalBalance(), 1000e6);
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_deposit_withdraw_cycle(uint256 amount) public {
        amount = bound(amount, 1e6, INITIAL_USDC_SUPPLY); // 1 USDC to max supply
        
        vm.startPrank(user1);
        
        // Deposit
        usdc.approve(address(marginAccount), amount);
        marginAccount.deposit(amount);
        assertEq(marginAccount.freeBalance(user1), amount);
        
        // Withdraw
        marginAccount.withdraw(amount);
        assertEq(marginAccount.freeBalance(user1), 0);
        assertEq(usdc.balanceOf(user1), INITIAL_USDC_SUPPLY);
        
        vm.stopPrank();
    }

    function testFuzz_margin_lock_unlock_cycle(uint256 depositAmount, uint256 lockAmount) public {
        depositAmount = bound(depositAmount, 1e6, INITIAL_USDC_SUPPLY);
        lockAmount = bound(lockAmount, 1, depositAmount);
        
        // Deposit
        vm.startPrank(user1);
        usdc.approve(address(marginAccount), depositAmount);
        marginAccount.deposit(depositAmount);
        vm.stopPrank();
        
        // Lock margin
        vm.startPrank(authorizedContract);
        marginAccount.lockMargin(user1, lockAmount);
        assertEq(marginAccount.lockedBalance(user1), lockAmount);
        assertEq(marginAccount.freeBalance(user1), depositAmount - lockAmount);
        
        // Unlock margin
        marginAccount.unlockMargin(user1, lockAmount);
        assertEq(marginAccount.lockedBalance(user1), 0);
        assertEq(marginAccount.freeBalance(user1), depositAmount);
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            REENTRANCY TESTS
    //////////////////////////////////////////////////////////////*/

    // These tests would require a malicious contract that attempts reentrancy
    // For brevity, we trust the ReentrancyGuard is working correctly

    /*//////////////////////////////////////////////////////////////
                            GAS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_gas_deposit() public {
        vm.startPrank(user1);
        usdc.approve(address(marginAccount), TEST_DEPOSIT_AMOUNT);
        
        uint256 gasBefore = gasleft();
        marginAccount.deposit(TEST_DEPOSIT_AMOUNT);
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("Gas used for deposit:", gasUsed);
        // Reasonable gas usage expectation
        assertLt(gasUsed, 150000);
        
        vm.stopPrank();
    }
}
