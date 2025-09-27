// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title InsuranceFund - Safety Net for Perpetual Futures Protocol
/// @notice Collects fees and covers bad debt to ensure system solvency
/// @dev This fund grows from trading fees and covers losses when margin is insufficient
contract InsuranceFund is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The USDC token contract
    IERC20 public immutable USDC;

    /// @notice Total USDC balance in the insurance fund
    uint256 public fundBalance;

    /// @notice Authorized contracts that can collect fees or cover bad debt
    mapping(address => bool) public authorized;

    /// @notice Minimum fund balance before triggering warnings
    uint256 public minFundBalance = 10000e6; // $10,000 USDC

    /// @notice Maximum single bad debt coverage amount
    uint256 public maxCoveragePerEvent = 100000e6; // $100,000 USDC

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event FundDeposit(address indexed depositor, uint256 amount, uint256 newBalance);
    event FeeCollected(address indexed source, uint256 amount, uint256 newBalance);
    event PenaltyCollected(address indexed source, uint256 amount, uint256 newBalance);
    event BadDebtCovered(address indexed recipient, uint256 amount, uint256 newBalance);
    event FundWithdraw(address indexed recipient, uint256 amount, uint256 newBalance);
    event AuthorizedContractAdded(address indexed contractAddress);
    event AuthorizedContractRemoved(address indexed contractAddress);
    event MinFundBalanceUpdated(uint256 oldBalance, uint256 newBalance);
    event MaxCoverageUpdated(uint256 oldMax, uint256 newMax);
    event LowFundWarning(uint256 currentBalance, uint256 minBalance);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InsufficientFundBalance();
    error ZeroAmount();
    error Unauthorized();
    error ExceedsMaxCoverage();
    error FundBalanceTooLow();

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyAuthorized() {
        if (!authorized[msg.sender] && msg.sender != owner()) {
            revert Unauthorized();
        }
        _;
    }

    modifier nonZeroAmount(uint256 amount) {
        if (amount == 0) revert ZeroAmount();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _usdc) Ownable(msg.sender) {
        USDC = IERC20(_usdc);
    }

    /*//////////////////////////////////////////////////////////////
                          FUNDING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit USDC into the insurance fund
    /// @param amount Amount of USDC to deposit
    function deposit(uint256 amount) external nonReentrant nonZeroAmount(amount) {
        // Transfer USDC from depositor to this contract
        USDC.safeTransferFrom(msg.sender, address(this), amount);

        // Update fund balance
        fundBalance += amount;

        emit FundDeposit(msg.sender, amount, fundBalance);
    }

    /// @notice Allow the protocol to top up the fund (owner only)
    /// @param amount Amount of USDC to add
    function fundTopUp(uint256 amount) external onlyOwner nonZeroAmount(amount) {
        USDC.safeTransferFrom(msg.sender, address(this), amount);
        fundBalance += amount;

        emit FundDeposit(msg.sender, amount, fundBalance);
    }

    /*//////////////////////////////////////////////////////////////
                      AUTHORIZED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Collect trading fees from authorized contracts
    /// @param amount Amount of fees to collect
    function collectFee(uint256 amount) external onlyAuthorized nonZeroAmount(amount) {
        // The fee should already be transferred to this contract by the caller
        // This function just updates our accounting
        fundBalance += amount;

        emit FeeCollected(msg.sender, amount, fundBalance);
    }

    /// @notice Collect penalties (e.g., liquidation penalties) from authorized contracts
    /// @param amount Amount of penalty to collect
    function collectPenalty(uint256 amount) external onlyAuthorized nonZeroAmount(amount) {
        // The penalty should already be transferred to this contract by the caller
        // This function just updates our accounting
        fundBalance += amount;

        emit PenaltyCollected(msg.sender, amount, fundBalance);
    }

    /// @notice Cover bad debt by transferring USDC to specified recipient
    /// @param recipient Address to receive the coverage (usually MarginAccount)
    /// @param amount Amount of bad debt to cover
    function coverBadDebt(address recipient, uint256 amount) 
        external 
        onlyAuthorized 
        nonZeroAmount(amount) 
    {
        if (amount > maxCoveragePerEvent) {
            revert ExceedsMaxCoverage();
        }

        if (fundBalance < amount) {
            revert InsufficientFundBalance();
        }

        // Update fund balance
        fundBalance -= amount;

        // Transfer USDC to recipient
        USDC.safeTransfer(recipient, amount);

        // Emit warning if fund is running low
        if (fundBalance < minFundBalance) {
            emit LowFundWarning(fundBalance, minFundBalance);
        }

        emit BadDebtCovered(recipient, amount, fundBalance);
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get current fund balance
    /// @return Current USDC balance in the fund
    function getBalance() external view returns (uint256) {
        return fundBalance;
    }

    /// @notice Get actual USDC balance held by this contract
    /// @return Contract's USDC balance
    function getContractBalance() external view returns (uint256) {
        return USDC.balanceOf(address(this));
    }

    /// @notice Check if fund balance is healthy
    /// @return True if fund balance is above minimum threshold
    function isHealthy() external view returns (bool) {
        return fundBalance >= minFundBalance;
    }

    /// @notice Check if contract USDC balance matches our accounting
    /// @return True if balances match
    function checkInvariant() external view returns (bool) {
        return USDC.balanceOf(address(this)) == fundBalance;
    }

    /// @notice Get fund utilization ratio (how much can be used for coverage)
    /// @return Utilization ratio in basis points (10000 = 100%)
    function getUtilizationRatio() external view returns (uint256) {
        if (fundBalance == 0) return 0;
        return (fundBalance * 10000) / maxCoveragePerEvent;
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Add an authorized contract
    /// @param contractAddress Address to authorize
    function addAuthorizedContract(address contractAddress) external onlyOwner {
        authorized[contractAddress] = true;
        emit AuthorizedContractAdded(contractAddress);
    }

    /// @notice Remove an authorized contract
    /// @param contractAddress Address to remove authorization
    function removeAuthorizedContract(address contractAddress) external onlyOwner {
        authorized[contractAddress] = false;
        emit AuthorizedContractRemoved(contractAddress);
    }

    /// @notice Update minimum fund balance threshold
    /// @param newMinBalance New minimum balance
    function setMinFundBalance(uint256 newMinBalance) external onlyOwner {
        uint256 oldBalance = minFundBalance;
        minFundBalance = newMinBalance;
        emit MinFundBalanceUpdated(oldBalance, newMinBalance);
    }

    /// @notice Update maximum coverage per event
    /// @param newMaxCoverage New maximum coverage amount
    function setMaxCoveragePerEvent(uint256 newMaxCoverage) external onlyOwner {
        uint256 oldMax = maxCoveragePerEvent;
        maxCoveragePerEvent = newMaxCoverage;
        emit MaxCoverageUpdated(oldMax, newMaxCoverage);
    }

    /// @notice Withdraw from fund (governance only, for excess funds)
    /// @param amount Amount to withdraw
    function withdraw(uint256 amount) external onlyOwner nonZeroAmount(amount) {
        if (fundBalance < amount) {
            revert InsufficientFundBalance();
        }

        // Ensure withdrawal doesn't bring balance below minimum
        if (fundBalance - amount < minFundBalance) {
            revert FundBalanceTooLow();
        }

        fundBalance -= amount;
        USDC.safeTransfer(owner(), amount);

        emit FundWithdraw(owner(), amount, fundBalance);
    }

    /// @notice Emergency function to recover non-USDC tokens
    /// @param token Token address
    /// @param amount Amount to recover
    function emergencyRecover(address token, uint256 amount) external onlyOwner {
        require(token != address(USDC), "Cannot recover USDC through this function");
        IERC20(token).safeTransfer(owner(), amount);
    }

    /// @notice Fix fund balance accounting if needed (emergency function)
    function fixInvariant() external onlyOwner {
        uint256 actualBalance = USDC.balanceOf(address(this));
        fundBalance = actualBalance;
    }

    /*//////////////////////////////////////////////////////////////
                        RECEIVE FUNCTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Allow direct USDC transfers to the fund (for fee collection)
    receive() external payable {
        revert("Use deposit() function for USDC");
    }
}
