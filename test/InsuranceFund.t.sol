// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {InsuranceFund} from "../src/InsuranceFund.sol";
import {MockUSDC} from "./utils/mocks/MockUSDC.sol";

contract InsuranceFundTest is Test {
    InsuranceFund public insuranceFund;
    MockUSDC public usdc;
    
    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public authorizedContract = makeAddr("authorizedContract");
    address public unauthorizedContract = makeAddr("unauthorizedContract");
    address public marginAccount = makeAddr("marginAccount");
    
    uint256 constant INITIAL_USDC_SUPPLY = 1_000_000e6; // 1M USDC
    uint256 constant INITIAL_FUND_AMOUNT = 50000e6; // 50K USDC
    uint256 constant TEST_FEE_AMOUNT = 100e6; // 100 USDC
    uint256 constant TEST_BAD_DEBT = 5000e6; // 5K USDC

    event FundDeposit(address indexed depositor, uint256 amount, uint256 newBalance);
    event FeeCollected(address indexed source, uint256 amount, uint256 newBalance);
    event PenaltyCollected(address indexed source, uint256 amount, uint256 newBalance);
    event BadDebtCovered(address indexed recipient, uint256 amount, uint256 newBalance);
    event FundWithdraw(address indexed recipient, uint256 amount, uint256 newBalance);
    event AuthorizedContractAdded(address indexed contractAddress);
    event AuthorizedContractRemoved(address indexed contractAddress);
    event LowFundWarning(uint256 currentBalance, uint256 minBalance);

    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy USDC mock
        usdc = new MockUSDC();
        usdc.mint(owner, INITIAL_USDC_SUPPLY);
        usdc.mint(user1, INITIAL_USDC_SUPPLY);
        usdc.mint(user2, INITIAL_USDC_SUPPLY);
        usdc.mint(authorizedContract, INITIAL_USDC_SUPPLY);
        
        // Deploy InsuranceFund
        insuranceFund = new InsuranceFund(address(usdc));
        
        // Add authorized contract
        insuranceFund.addAuthorizedContract(authorizedContract);
        
        // Fund the insurance fund initially
        usdc.approve(address(insuranceFund), INITIAL_FUND_AMOUNT);
        insuranceFund.deposit(INITIAL_FUND_AMOUNT);
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_deployment() public {
        assertEq(address(insuranceFund.USDC()), address(usdc));
        assertEq(insuranceFund.owner(), owner);
        assertTrue(insuranceFund.authorized(authorizedContract));
        assertFalse(insuranceFund.authorized(unauthorizedContract));
        assertEq(insuranceFund.minFundBalance(), 10000e6); // Default $10K
        assertEq(insuranceFund.maxCoveragePerEvent(), 100000e6); // Default $100K
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_deposit_success() public {
        uint256 depositAmount = 1000e6;
        uint256 expectedBalance = INITIAL_FUND_AMOUNT + depositAmount;
        
        vm.startPrank(user1);
        usdc.approve(address(insuranceFund), depositAmount);
        
        vm.expectEmit(true, false, false, true);
        emit FundDeposit(user1, depositAmount, expectedBalance);
        
        insuranceFund.deposit(depositAmount);
        
        assertEq(insuranceFund.getBalance(), expectedBalance);
        assertEq(insuranceFund.getContractBalance(), expectedBalance);
        
        vm.stopPrank();
    }

    function test_fundTopUp_owner_only() public {
        uint256 topUpAmount = 2000e6;
        uint256 expectedBalance = INITIAL_FUND_AMOUNT + topUpAmount;
        
        vm.startPrank(owner);
        usdc.approve(address(insuranceFund), topUpAmount);
        
        vm.expectEmit(true, false, false, true);
        emit FundDeposit(owner, topUpAmount, expectedBalance);
        
        insuranceFund.fundTopUp(topUpAmount);
        
        assertEq(insuranceFund.getBalance(), expectedBalance);
        
        vm.stopPrank();
    }

    function test_fundTopUp_revert_non_owner() public {
        vm.startPrank(user1);
        
        vm.expectRevert();
        insuranceFund.fundTopUp(1000e6);
        
        vm.stopPrank();
    }

    function test_deposit_revert_zero_amount() public {
        vm.startPrank(user1);
        
        vm.expectRevert(InsuranceFund.ZeroAmount.selector);
        insuranceFund.deposit(0);
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            FEE COLLECTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_collectFee_success() public {
        uint256 expectedBalance = INITIAL_FUND_AMOUNT + TEST_FEE_AMOUNT;
        
        // Transfer fee to insurance fund first (simulating hook behavior)
        vm.startPrank(authorizedContract);
        usdc.transfer(address(insuranceFund), TEST_FEE_AMOUNT);
        
        vm.expectEmit(true, false, false, true);
        emit FeeCollected(authorizedContract, TEST_FEE_AMOUNT, expectedBalance);
        
        insuranceFund.collectFee(TEST_FEE_AMOUNT);
        
        assertEq(insuranceFund.getBalance(), expectedBalance);
        
        vm.stopPrank();
    }

    function test_collectPenalty_success() public {
        uint256 penaltyAmount = 250e6;
        uint256 expectedBalance = INITIAL_FUND_AMOUNT + penaltyAmount;
        
        vm.startPrank(authorizedContract);
        usdc.transfer(address(insuranceFund), penaltyAmount);
        
        vm.expectEmit(true, false, false, true);
        emit PenaltyCollected(authorizedContract, penaltyAmount, expectedBalance);
        
        insuranceFund.collectPenalty(penaltyAmount);
        
        assertEq(insuranceFund.getBalance(), expectedBalance);
        
        vm.stopPrank();
    }

    function test_collectFee_revert_unauthorized() public {
        vm.startPrank(unauthorizedContract);
        
        vm.expectRevert(InsuranceFund.Unauthorized.selector);
        insuranceFund.collectFee(TEST_FEE_AMOUNT);
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            BAD DEBT COVERAGE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_coverBadDebt_success() public {
        uint256 expectedBalance = INITIAL_FUND_AMOUNT - TEST_BAD_DEBT;
        uint256 marginAccountBalanceBefore = usdc.balanceOf(marginAccount);
        
        vm.startPrank(authorizedContract);
        
        vm.expectEmit(true, false, false, true);
        emit BadDebtCovered(marginAccount, TEST_BAD_DEBT, expectedBalance);
        
        insuranceFund.coverBadDebt(marginAccount, TEST_BAD_DEBT);
        
        assertEq(insuranceFund.getBalance(), expectedBalance);
        assertEq(usdc.balanceOf(marginAccount), marginAccountBalanceBefore + TEST_BAD_DEBT);
        
        vm.stopPrank();
    }

    function test_coverBadDebt_low_fund_warning() public {
        // Reduce fund to just above minimum
        uint256 withdrawAmount = INITIAL_FUND_AMOUNT - 12000e6; // Leave 12K (above 10K min)
        vm.startPrank(owner);
        insuranceFund.withdraw(withdrawAmount);
        vm.stopPrank();
        
        // Cover debt that brings it below minimum
        uint256 badDebt = 5000e6; // Will leave 7K (below 10K min)
        
        vm.startPrank(authorizedContract);
        
        vm.expectEmit(false, false, false, true);
        emit LowFundWarning(7000e6, 10000e6);
        
        insuranceFund.coverBadDebt(marginAccount, badDebt);
        
        assertFalse(insuranceFund.isHealthy());
        
        vm.stopPrank();
    }

    function test_coverBadDebt_revert_insufficient_funds() public {
        uint256 hugeBadDebt = INITIAL_FUND_AMOUNT + 1000e6; // More than available
        
        vm.startPrank(authorizedContract);
        
        vm.expectRevert(InsuranceFund.InsufficientFundBalance.selector);
        insuranceFund.coverBadDebt(marginAccount, hugeBadDebt);
        
        vm.stopPrank();
    }

    function test_coverBadDebt_revert_exceeds_max_coverage() public {
        // Try to cover more than max coverage per event
        uint256 excessiveBadDebt = 150000e6; // More than 100K max
        
        vm.startPrank(authorizedContract);
        
        vm.expectRevert(InsuranceFund.ExceedsMaxCoverage.selector);
        insuranceFund.coverBadDebt(marginAccount, excessiveBadDebt);
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_withdraw_success() public {
        uint256 withdrawAmount = 5000e6;
        uint256 expectedBalance = INITIAL_FUND_AMOUNT - withdrawAmount;
        uint256 ownerBalanceBefore = usdc.balanceOf(owner);
        
        vm.startPrank(owner);
        
        vm.expectEmit(true, false, false, true);
        emit FundWithdraw(owner, withdrawAmount, expectedBalance);
        
        insuranceFund.withdraw(withdrawAmount);
        
        assertEq(insuranceFund.getBalance(), expectedBalance);
        assertEq(usdc.balanceOf(owner), ownerBalanceBefore + withdrawAmount);
        
        vm.stopPrank();
    }

    function test_withdraw_revert_below_minimum() public {
        // Try to withdraw too much (would leave less than minimum)
        uint256 withdrawAmount = INITIAL_FUND_AMOUNT - 5000e6; // Would leave 5K (below 10K min)
        
        vm.startPrank(owner);
        
        vm.expectRevert(InsuranceFund.FundBalanceTooLow.selector);
        insuranceFund.withdraw(withdrawAmount);
        
        vm.stopPrank();
    }

    function test_withdraw_revert_non_owner() public {
        vm.startPrank(user1);
        
        vm.expectRevert();
        insuranceFund.withdraw(1000e6);
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            CONFIGURATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setMinFundBalance() public {
        uint256 newMinBalance = 20000e6; // 20K
        
        vm.startPrank(owner);
        
        vm.expectEmit(false, false, false, true);
        emit InsuranceFund.MinFundBalanceUpdated(10000e6, newMinBalance);
        
        insuranceFund.setMinFundBalance(newMinBalance);
        
        assertEq(insuranceFund.minFundBalance(), newMinBalance);
        
        vm.stopPrank();
    }

    function test_setMaxCoveragePerEvent() public {
        uint256 newMaxCoverage = 200000e6; // 200K
        
        vm.startPrank(owner);
        
        vm.expectEmit(false, false, false, true);
        emit InsuranceFund.MaxCoverageUpdated(100000e6, newMaxCoverage);
        
        insuranceFund.setMaxCoveragePerEvent(newMaxCoverage);
        
        assertEq(insuranceFund.maxCoveragePerEvent(), newMaxCoverage);
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_isHealthy() public {
        assertTrue(insuranceFund.isHealthy()); // 50K > 10K minimum
        
        // Use bad debt coverage to bring fund below minimum (can't withdraw below minimum directly)
        vm.startPrank(authorizedContract);
        
        // Cover bad debt that brings fund to exactly minimum
        uint256 badDebtToBringToMinimum = INITIAL_FUND_AMOUNT - insuranceFund.minFundBalance();
        insuranceFund.coverBadDebt(marginAccount, badDebtToBringToMinimum);
        
        // Fund should still be healthy at exactly minimum
        assertTrue(insuranceFund.isHealthy());
        
        // Cover additional bad debt to go below minimum  
        insuranceFund.coverBadDebt(marginAccount, 1000e6); // Now below minimum
        
        // Fund should now be unhealthy
        assertFalse(insuranceFund.isHealthy());
        
        vm.stopPrank();
    }

    function test_getUtilizationRatio() public {
        // With 50K fund and 100K max coverage = 50% utilization = 5000 bps
        uint256 ratio = insuranceFund.getUtilizationRatio();
        assertEq(ratio, 5000); // 50% in basis points
        
        // With 0 fund
        vm.startPrank(owner);
        insuranceFund.withdraw(INITIAL_FUND_AMOUNT - insuranceFund.minFundBalance());
        vm.stopPrank();
        
        ratio = insuranceFund.getUtilizationRatio();
        assertEq(ratio, 1000); // 10% (10K / 100K)
    }

    function test_checkInvariant() public {
        assertTrue(insuranceFund.checkInvariant());
        
        // After operations
        vm.startPrank(user1);
        usdc.approve(address(insuranceFund), 1000e6);
        insuranceFund.deposit(1000e6);
        vm.stopPrank();
        
        assertTrue(insuranceFund.checkInvariant());
    }

    /*//////////////////////////////////////////////////////////////
                            AUTHORIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_addRemoveAuthorizedContract() public {
        address newContract = makeAddr("newContract");
        
        vm.startPrank(owner);
        
        // Add
        vm.expectEmit(true, false, false, false);
        emit AuthorizedContractAdded(newContract);
        
        insuranceFund.addAuthorizedContract(newContract);
        assertTrue(insuranceFund.authorized(newContract));
        
        // Remove
        vm.expectEmit(true, false, false, false);
        emit AuthorizedContractRemoved(newContract);
        
        insuranceFund.removeAuthorizedContract(newContract);
        assertFalse(insuranceFund.authorized(newContract));
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            INTEGRATION SCENARIO TESTS
    //////////////////////////////////////////////////////////////*/

    function test_full_lifecycle_scenario() public {
        // Scenario: Collect fees, cover bad debt, check health
        
        // 1. Collect some fees
        vm.startPrank(authorizedContract);
        usdc.transfer(address(insuranceFund), 1000e6);
        insuranceFund.collectFee(1000e6);
        vm.stopPrank();
        
        uint256 balanceAfterFees = INITIAL_FUND_AMOUNT + 1000e6;
        assertEq(insuranceFund.getBalance(), balanceAfterFees);
        
        // 2. Cover some bad debt
        vm.startPrank(authorizedContract);
        insuranceFund.coverBadDebt(marginAccount, 5000e6);
        vm.stopPrank();
        
        uint256 balanceAfterCoverage = balanceAfterFees - 5000e6;
        assertEq(insuranceFund.getBalance(), balanceAfterCoverage);
        
        // 3. Check health (should still be healthy)
        assertTrue(insuranceFund.isHealthy());
        
        // 4. Owner withdraws excess
        vm.startPrank(owner);
        uint256 excess = balanceAfterCoverage - insuranceFund.minFundBalance() - 1000e6; // Leave 1K buffer
        insuranceFund.withdraw(excess);
        vm.stopPrank();
        
        assertTrue(insuranceFund.isHealthy());
    }

    /*//////////////////////////////////////////////////////////////
                            STRESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_multiple_bad_debt_coverage() public {
        uint256 badDebtAmount = 2000e6;
        
        vm.startPrank(authorizedContract);
        
        // Cover bad debt 5 times
        for (uint256 i = 0; i < 5; i++) {
            insuranceFund.coverBadDebt(marginAccount, badDebtAmount);
        }
        
        uint256 expectedBalance = INITIAL_FUND_AMOUNT - (badDebtAmount * 5);
        assertEq(insuranceFund.getBalance(), expectedBalance);
        assertEq(usdc.balanceOf(marginAccount), badDebtAmount * 5);
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_deposit_withdraw_cycle(uint256 amount) public {
        amount = bound(amount, 1e6, 100000e6); // 1 USDC to 100K USDC
        
        vm.startPrank(user1);
        
        // Deposit
        usdc.approve(address(insuranceFund), amount);
        insuranceFund.deposit(amount);
        
        uint256 balanceAfterDeposit = INITIAL_FUND_AMOUNT + amount;
        assertEq(insuranceFund.getBalance(), balanceAfterDeposit);
        
        vm.stopPrank();
        
        // Owner withdraws (keeping minimum)
        vm.startPrank(owner);
        
        if (balanceAfterDeposit > insuranceFund.minFundBalance()) {
            uint256 withdrawable = balanceAfterDeposit - insuranceFund.minFundBalance();
            insuranceFund.withdraw(withdrawable);
            assertEq(insuranceFund.getBalance(), insuranceFund.minFundBalance());
        }
        
        vm.stopPrank();
    }

    function testFuzz_badDebt_coverage(uint256 badDebt) public {
        badDebt = bound(badDebt, 1e6, insuranceFund.maxCoveragePerEvent());
        
        // Ensure fund can cover it
        vm.assume(badDebt <= INITIAL_FUND_AMOUNT);
        
        vm.startPrank(authorizedContract);
        
        insuranceFund.coverBadDebt(marginAccount, badDebt);
        
        assertEq(insuranceFund.getBalance(), INITIAL_FUND_AMOUNT - badDebt);
        assertEq(usdc.balanceOf(marginAccount), badDebt);
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            EMERGENCY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_emergencyRecover_non_usdc() public {
        // Deploy a different token
        MockUSDC otherToken = new MockUSDC();
        otherToken.mint(address(insuranceFund), 1000e6);
        
        vm.startPrank(owner);
        
        insuranceFund.emergencyRecover(address(otherToken), 1000e6);
        
        assertEq(otherToken.balanceOf(owner), 1000e6);
        
        vm.stopPrank();
    }

    function test_emergencyRecover_revert_usdc() public {
        vm.startPrank(owner);
        
        vm.expectRevert("Cannot recover USDC through this function");
        insuranceFund.emergencyRecover(address(usdc), 1000e6);
        
        vm.stopPrank();
    }

    function test_fixInvariant() public {
        // Simulate invariant violation
        vm.startPrank(user1);
        usdc.transfer(address(insuranceFund), 1000e6);
        vm.stopPrank();
        
        assertFalse(insuranceFund.checkInvariant());
        
        vm.startPrank(owner);
        insuranceFund.fixInvariant();
        vm.stopPrank();
        
        assertTrue(insuranceFund.checkInvariant());
        assertEq(insuranceFund.getBalance(), INITIAL_FUND_AMOUNT + 1000e6);
    }
}
