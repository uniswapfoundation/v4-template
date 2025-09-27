// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MarginAccount - USDC Collateral Vault for Perpetual Futures
/// @notice Centralized vault that holds all user collateral (USDC) and manages margin for trading
/// @dev This contract is the single source of truth for all USDC balances in the perp system
contract MarginAccount is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The USDC token contract
    IERC20 public immutable USDC;

    /// @notice User's free balance (can be withdrawn or used as margin)
    mapping(address => uint256) public freeBalance;

    /// @notice User's locked balance (used as margin for active positions)
    mapping(address => uint256) public lockedBalance;

    /// @notice Total amount of USDC held by this contract
    uint256 public totalBalance;

    /// @notice Authorized contracts that can call lock/unlock/settle functions
    mapping(address => bool) public authorized;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposit(address indexed user, uint256 amount, uint256 newFreeBalance);
    event Withdraw(address indexed user, uint256 amount, uint256 newFreeBalance);
    event MarginLocked(address indexed user, uint256 amount, uint256 newLockedBalance);
    event MarginUnlocked(address indexed user, uint256 amount, uint256 newFreeBalance);
    event PnLSettled(address indexed user, int256 pnl, uint256 newFreeBalance);
    event FundingApplied(address indexed user, int256 fundingAmount, uint256 newFreeBalance, uint256 newLockedBalance);
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event AuthorizedContractAdded(address indexed contractAddress);
    event AuthorizedContractRemoved(address indexed contractAddress);
    event BalanceInvariantViolation();

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InsufficientFreeBalance();
    error InsufficientLockedBalance();
    error InsufficientTotalBalance();
    error ZeroAmount();
    error Unauthorized();

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
                          USER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit USDC into the vault
    /// @param amount Amount of USDC to deposit
    function deposit(uint256 amount) external nonReentrant nonZeroAmount(amount) {
        // Transfer USDC from user to this contract
        USDC.safeTransferFrom(msg.sender, address(this), amount);

        // Update balances
        freeBalance[msg.sender] += amount;
        totalBalance += amount;

        emit Deposit(msg.sender, amount, freeBalance[msg.sender]);
    }

    /// @notice Withdraw USDC from free balance
    /// @param amount Amount of USDC to withdraw
    function withdraw(uint256 amount) external nonReentrant nonZeroAmount(amount) {
        if (freeBalance[msg.sender] < amount) {
            revert InsufficientFreeBalance();
        }

        // Update balances
        freeBalance[msg.sender] -= amount;
        totalBalance -= amount;

        // Transfer USDC to user
        USDC.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount, freeBalance[msg.sender]);
    }

    /// @notice Withdraw USDC to user's address on behalf of user (for authorized contracts)
    /// @param user User to withdraw for
    /// @param amount Amount of USDC to withdraw
    function withdrawFor(address user, uint256 amount) 
        external 
        onlyAuthorized 
        nonReentrant 
        nonZeroAmount(amount) 
    {
        if (freeBalance[user] < amount) {
            revert InsufficientFreeBalance();
        }

        // Update balances
        freeBalance[user] -= amount;
        totalBalance -= amount;

        // Transfer USDC to user
        USDC.safeTransfer(user, amount);

        emit Withdraw(user, amount, freeBalance[user]);
    }

    /*//////////////////////////////////////////////////////////////
                      AUTHORIZED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Lock margin from user's free balance for a position
    /// @param user User address
    /// @param amount Amount to lock
    function lockMargin(address user, uint256 amount) 
        external 
        onlyAuthorized 
        nonZeroAmount(amount) 
    {
        if (freeBalance[user] < amount) {
            revert InsufficientFreeBalance();
        }

        // Move from free to locked
        freeBalance[user] -= amount;
        lockedBalance[user] += amount;

        emit MarginLocked(user, amount, lockedBalance[user]);
    }

    /// @notice Unlock margin back to user's free balance
    /// @param user User address  
    /// @param amount Amount to unlock
    function unlockMargin(address user, uint256 amount)
        external
        onlyAuthorized
        nonZeroAmount(amount)
    {
        if (lockedBalance[user] < amount) {
            revert InsufficientLockedBalance();
        }

        // Move from locked to free
        lockedBalance[user] -= amount;
        freeBalance[user] += amount;

        emit MarginUnlocked(user, amount, freeBalance[user]);
    }

    /// @notice Settle profit/loss for a user
    /// @param user User address
    /// @param pnl Profit (positive) or loss (negative) amount
    function settlePnL(address user, int256 pnl) external onlyAuthorized {
        if (pnl > 0) {
            // User made profit - credit their free balance
            uint256 profit = uint256(pnl);
            freeBalance[user] += profit;
            totalBalance += profit;
        } else if (pnl < 0) {
            // User made loss - deduct from their locked balance first, then free
            uint256 loss = uint256(-pnl);
            
            uint256 lockedAmount = lockedBalance[user];
            uint256 freeAmount = freeBalance[user];
            
            if (lockedAmount >= loss) {
                // Loss covered by locked balance
                lockedBalance[user] -= loss;
            } else {
                // Loss exceeds locked balance - use all locked + some free
                uint256 remainingLoss = loss - lockedAmount;
                lockedBalance[user] = 0;
                
                if (freeAmount >= remainingLoss) {
                    freeBalance[user] -= remainingLoss;
                } else {
                    // Insufficient total balance - this should not happen in normal operation
                    // This would be a bad debt scenario
                    freeBalance[user] = 0;
                    revert InsufficientTotalBalance();
                }
            }
            
            totalBalance -= loss;
        }

        emit PnLSettled(user, pnl, freeBalance[user]);
    }

    /// @notice Deposit USDC on behalf of a user (for authorized contracts)
    /// @param user User to credit
    /// @param amount Amount to deposit (must be already transferred to this contract)
    function depositFor(address user, uint256 amount) 
        external 
        onlyAuthorized 
        nonZeroAmount(amount) 
    {
        // USDC should already be transferred to this contract by the caller
        // Update balances
        freeBalance[user] += amount;
        totalBalance += amount;

        emit Deposit(user, amount, freeBalance[user]);
    }

    /// @notice Apply funding payment (positive = user receives, negative = user pays)
    /// @param user User address
    /// @param fundingAmount Funding amount (can be positive or negative)
    function applyFunding(address user, int256 fundingAmount) external onlyAuthorized {
        if (fundingAmount == 0) return;

        if (fundingAmount > 0) {
            // User receives funding - credit their free balance
            uint256 amount = uint256(fundingAmount);
            freeBalance[user] += amount;
            totalBalance += amount;
        } else {
            // User pays funding - deduct from free balance first, then locked
            uint256 amount = uint256(-fundingAmount);
            
            uint256 freeAmount = freeBalance[user];
            uint256 lockedAmount = lockedBalance[user];
            
            if (freeAmount >= amount) {
                freeBalance[user] -= amount;
            } else if (freeAmount + lockedAmount >= amount) {
                // Use all free + some locked
                uint256 remainingAmount = amount - freeAmount;
                freeBalance[user] = 0;
                lockedBalance[user] -= remainingAmount;
            } else {
                // Insufficient balance - this could lead to liquidation
                revert InsufficientTotalBalance();
            }
            
            totalBalance -= amount;
        }

        emit FundingApplied(user, fundingAmount, freeBalance[user], lockedBalance[user]);
    }

    /// @notice Transfer funds from one user to another (for liquidation fees)
    /// @param from User to transfer from
    /// @param to User to transfer to  
    /// @param amount Amount to transfer
    function transferBetweenUsers(address from, address to, uint256 amount) 
        external 
        onlyAuthorized 
        nonZeroAmount(amount) 
    {
        if (freeBalance[from] < amount) {
            revert InsufficientFreeBalance();
        }

        // Transfer from free balance of 'from' to free balance of 'to'
        freeBalance[from] -= amount;
        freeBalance[to] += amount;

        emit Transfer(from, to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get total balance for a user (free + locked)
    /// @param user User address
    /// @return Total balance
    function getTotalBalance(address user) external view returns (uint256) {
        return freeBalance[user] + lockedBalance[user];
    }

    /// @notice Get user's available balance (free balance only)
    /// @param user User address
    /// @return Free balance
    function getAvailableBalance(address user) external view returns (uint256) {
        return freeBalance[user];
    }

    /// @notice Get user's locked balance
    /// @param user User address
    /// @return Locked balance
    function getLockedBalance(address user) external view returns (uint256) {
        return lockedBalance[user];
    }

    /// @notice Get the total USDC balance held by this contract
    /// @return Contract's USDC balance
    function getContractBalance() external view returns (uint256) {
        return USDC.balanceOf(address(this));
    }

    /// @notice Check if contract USDC balance matches our accounting
    /// @return True if balances match
    function checkInvariant() external view returns (bool) {
        return USDC.balanceOf(address(this)) == totalBalance;
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

    /// @notice Emergency function to recover tokens (only for non-USDC tokens)
    /// @param token Token address
    /// @param amount Amount to recover
    function emergencyRecover(address token, uint256 amount) external onlyOwner {
        require(token != address(USDC), "Cannot recover USDC");
        IERC20(token).safeTransfer(owner(), amount);
    }

    /// @notice Verify and fix balance invariants (emergency function)
    function fixInvariant() external onlyOwner {
        uint256 actualBalance = USDC.balanceOf(address(this));
        if (actualBalance != totalBalance) {
            totalBalance = actualBalance;
            emit BalanceInvariantViolation();
        }
    }
}
