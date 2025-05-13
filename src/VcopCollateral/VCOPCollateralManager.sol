// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "v4-core/lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {VCOPCollateralized} from "./VCOPCollateralized.sol";
import {VCOPOracle} from "./VCOPOracle.sol";
import {console2 as console} from "forge-std/console2.sol";

/**
 * @title VCOPCollateralManager
 * @notice Manages collateral for the VCOP stablecoin
 */
contract VCOPCollateralManager is Ownable {
    using SafeERC20 for IERC20;
    
    // VCOP token contract
    VCOPCollateralized public vcop;
    
    // Price oracle
    VCOPOracle public oracle;
    
    // Collateral configuration
    struct CollateralAsset {
        address token;
        uint256 ratio;      // Collateralization ratio (150% = 1500000)
        uint256 mintFee;    // Fee when minting (0.1% = 1000)
        uint256 burnFee;    // Fee when burning (0.1% = 1000)
        uint256 liquidationThreshold; // Below this ratio, liquidation happens (120% = 1200000)
        bool active;
    }
    
    // Supported collateral assets
    mapping(address => CollateralAsset) public collaterals;
    address[] public collateralList;
    
    // Token identifiers for automated deployment
    mapping(address => string) public tokenIdentifiers;
    
    // User collateral positions
    struct Position {
        address collateralToken;
        uint256 collateralAmount;
        uint256 vcopMinted;
    }
    
    // User positions (user => position ID => Position)
    mapping(address => mapping(uint256 => Position)) public positions;
    mapping(address => uint256) public positionCount;
    
    // Fee collector
    address public feeCollector;
    
    // Events
    event CollateralAdded(address token, uint256 ratio);
    event CollateralRemoved(address token);
    event PositionCreated(address user, uint256 positionId, address token, uint256 collateralAmount, uint256 vcopMinted);
    event CollateralDeposited(address user, uint256 positionId, uint256 amount);
    event CollateralWithdrawn(address user, uint256 positionId, uint256 amount);
    event PositionLiquidated(address user, uint256 positionId, address liquidator);
    event VCOPMinted(address user, uint256 amount);
    event VCOPBurned(address user, uint256 amount);
    
    constructor(address _vcop, address _oracle) Ownable(msg.sender) {
        vcop = VCOPCollateralized(_vcop);
        oracle = VCOPOracle(_oracle);
        feeCollector = msg.sender;
    }
    
    /**
     * @dev Sets the fee collector address
     */
    function setFeeCollector(address _collector) external onlyOwner {
        require(_collector != address(0), "Zero address not allowed");
        feeCollector = _collector;
    }
    
    /**
     * @dev Adds or updates a collateral asset
     */
    function configureCollateral(
        address token,
        uint256 ratio,
        uint256 mintFee,
        uint256 burnFee,
        uint256 liquidationThreshold,
        bool active
    ) external onlyOwner {
        require(token != address(0), "Invalid token address");
        require(ratio >= 1000000, "Ratio must be at least 100%");
        require(liquidationThreshold < ratio, "Liquidation threshold must be below ratio");
        
        if (collaterals[token].token == address(0)) {
            collateralList.push(token);
        }
        
        collaterals[token] = CollateralAsset({
            token: token,
            ratio: ratio,
            mintFee: mintFee,
            burnFee: burnFee,
            liquidationThreshold: liquidationThreshold,
            active: active
        });
        
        emit CollateralAdded(token, ratio);
    }
    
    /**
     * @dev Registers a token identifier for automated deployment
     */
    function registerTokenIdentifier(address token, string calldata identifier) external onlyOwner {
        tokenIdentifiers[token] = identifier;
    }
    
    /**
     * @dev Creates a new collateralized position
     */
    function createPosition(address collateralToken, uint256 collateralAmount, uint256 vcopToMint) external {
        CollateralAsset memory asset = collaterals[collateralToken];
        require(asset.active, "Collateral not supported or inactive");
        
        // Check maximum VCOP that can be minted with provided collateral
        uint256 maxVcop = getMaxVCOPforCollateral(collateralToken, collateralAmount);
        require(vcopToMint <= maxVcop, "Insufficient collateral for requested amount");
        
        // Transfer collateral to this contract
        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), collateralAmount);
        
        // Calculate fee
        uint256 fee = (vcopToMint * asset.mintFee) / 1000000;
        
        // Create position
        uint256 positionId = positionCount[msg.sender];
        positionCount[msg.sender] += 1;
        
        positions[msg.sender][positionId] = Position({
            collateralToken: collateralToken,
            collateralAmount: collateralAmount,
            vcopMinted: vcopToMint
        });
        
        // Mint VCOP to user (minus fee)
        vcop.mint(msg.sender, vcopToMint - fee);
        if (fee > 0) {
            vcop.mint(feeCollector, fee);
        }
        
        emit PositionCreated(msg.sender, positionId, collateralToken, collateralAmount, vcopToMint);
        emit VCOPMinted(msg.sender, vcopToMint - fee);
    }
    
    /**
     * @dev Adds more collateral to an existing position
     */
    function addCollateral(uint256 positionId, uint256 amount) external {
        Position storage position = positions[msg.sender][positionId];
        require(position.collateralAmount > 0, "Position does not exist");
        
        IERC20(position.collateralToken).safeTransferFrom(msg.sender, address(this), amount);
        position.collateralAmount += amount;
        
        emit CollateralDeposited(msg.sender, positionId, amount);
    }
    
    /**
     * @dev Withdraws collateral from a position if collateralization ratio permits
     */
    function withdrawCollateral(uint256 positionId, uint256 amount) external {
        Position storage position = positions[msg.sender][positionId];
        require(position.collateralAmount > 0, "Position does not exist");
        require(amount <= position.collateralAmount, "Amount exceeds available collateral");
        
        // Check if remaining collateral is sufficient
        uint256 remainingCollateral = position.collateralAmount - amount;
        uint256 minCollateralRequired = getMinCollateralForVCOP(
            position.collateralToken, 
            position.vcopMinted
        );
        
        require(remainingCollateral >= minCollateralRequired, "Withdrawal would breach collateral ratio");
        
        // Update position and transfer tokens
        position.collateralAmount = remainingCollateral;
        IERC20(position.collateralToken).safeTransfer(msg.sender, amount);
        
        emit CollateralWithdrawn(msg.sender, positionId, amount);
    }
    
    /**
     * @dev Repays VCOP debt and retrieves collateral
     */
    function repayDebt(uint256 positionId, uint256 vcpAmount) external {
        Position storage position = positions[msg.sender][positionId];
        require(position.collateralAmount > 0, "Position does not exist");
        
        uint256 toRepay = vcpAmount;
        if (toRepay > position.vcopMinted) {
            toRepay = position.vcopMinted;
        }
        
        CollateralAsset memory asset = collaterals[position.collateralToken];
        uint256 fee = (toRepay * asset.burnFee) / 1000000;
        
        // Burn VCOP from user
        vcop.burn(msg.sender, toRepay);
        
        // Transfer fee if any
        if (fee > 0) {
            vcop.mint(feeCollector, fee);
        }
        
        // Update position
        position.vcopMinted -= toRepay;
        
        // If all debt repaid, return all collateral
        if (position.vcopMinted == 0) {
            uint256 collateralToReturn = position.collateralAmount;
            IERC20(position.collateralToken).safeTransfer(msg.sender, collateralToReturn);
            
            // Clear position
            position.collateralAmount = 0;
            
            emit CollateralWithdrawn(msg.sender, positionId, collateralToReturn);
        }
        
        emit VCOPBurned(msg.sender, toRepay);
    }
    
    /**
     * @dev Liquidates an undercollateralized position
     */
    function liquidatePosition(address user, uint256 positionId) external {
        Position storage position = positions[user][positionId];
        require(position.collateralAmount > 0, "Position does not exist");
        
        uint256 currentRatio = getCurrentCollateralRatio(user, positionId);
        CollateralAsset memory asset = collaterals[position.collateralToken];
        
        require(currentRatio < asset.liquidationThreshold, "Position not liquidatable");
        
        // Transfer collateral to liquidator with bonus
        uint256 collateralForLiquidator = position.collateralAmount;
        IERC20(position.collateralToken).safeTransfer(msg.sender, collateralForLiquidator);
        
        // Burn VCOP debt
        vcop.burn(msg.sender, position.vcopMinted);
        
        // Clear position
        position.collateralAmount = 0;
        position.vcopMinted = 0;
        
        emit PositionLiquidated(user, positionId, msg.sender);
    }
    
    /**
     * @dev Calculates current collateralization ratio for a position
     */
    function getCurrentCollateralRatio(address user, uint256 positionId) public view returns (uint256) {
        Position memory position = positions[user][positionId];
        if (position.vcopMinted == 0) return type(uint256).max;
        
        // Get collateral price and calculate ratio
        uint256 collateralValue = getCollateralValue(position.collateralToken, position.collateralAmount);
        return (collateralValue * 1000000) / position.vcopMinted;
    }
    
    /**
     * @dev Calculates maximum VCOP that can be minted for a given collateral amount
     */
    function getMaxVCOPforCollateral(address collateralToken, uint256 amount) public view returns (uint256) {
        uint256 collateralValue = getCollateralValue(collateralToken, amount);
        CollateralAsset memory asset = collaterals[collateralToken];
        return (collateralValue * 1000000) / asset.ratio;
    }
    
    /**
     * @dev Calculates minimum collateral needed for a certain amount of VCOP
     */
    function getMinCollateralForVCOP(address collateralToken, uint256 vcopAmount) public view returns (uint256) {
        CollateralAsset memory asset = collaterals[collateralToken];
        uint256 collateralValueNeeded = (vcopAmount * asset.ratio) / 1000000;
        return getCollateralAmountForValue(collateralToken, collateralValueNeeded);
    }
    
    /**
     * @dev Calculates the value of collateral in terms of VCOP
     */
    function getCollateralValue(address collateralToken, uint256 amount) public view returns (uint256) {
        bytes32 tokenType = keccak256(abi.encodePacked(tokenIdentifiers[collateralToken]));
        
        // Handle USDC type tokens
        if (tokenType == keccak256(abi.encodePacked("USDC"))) {
            uint256 usdToCop = oracle.getUsdToCopRateView();
            return (amount * usdToCop) / 1e6;
        }
        
        return 0; // For other tokens, implement accordingly
    }
    
    /**
     * @dev Calculates amount of collateral for a given value
     */
    function getCollateralAmountForValue(address collateralToken, uint256 value) public view returns (uint256) {
        bytes32 tokenType = keccak256(abi.encodePacked(tokenIdentifiers[collateralToken]));
        
        // Handle USDC type tokens
        if (tokenType == keccak256(abi.encodePacked("USDC"))) {
            uint256 usdToCop = oracle.getUsdToCopRateView();
            return (value * 1e6) / usdToCop;
        }
        
        return 0; // For other tokens, implement accordingly
    }
}