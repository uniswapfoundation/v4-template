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
    
    // PSM (Peg Stability Module) configuration
    struct PSMReserve {
        uint256 collateralAmount;
        uint256 vcopAmount;
        bool active;
    }
    
    // Supported collateral assets
    mapping(address => CollateralAsset) public collaterals;
    address[] public collateralList;
    
    // PSM reserves by collateral token
    mapping(address => PSMReserve) public psmReserves;
    
    // Address of PSM hook authorized to manage PSM reserves
    address public psmHookAddress;
    
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
    
    // PSM stats
    uint256 public lastPSMOperationTimestamp;
    uint256 public totalPSMSwapsCount;
    
    // Events
    event CollateralAdded(address token, uint256 ratio);
    event CollateralRemoved(address token);
    event PositionCreated(address user, uint256 positionId, address token, uint256 collateralAmount, uint256 vcopMinted);
    event CollateralDeposited(address user, uint256 positionId, uint256 amount);
    event CollateralWithdrawn(address user, uint256 positionId, uint256 amount);
    event PositionLiquidated(address user, uint256 positionId, address liquidator);
    event VCOPMinted(address user, uint256 amount);
    event VCOPBurned(address user, uint256 amount);
    
    // PSM events
    event PSMReserveAdded(address token, uint256 amount);
    event PSMReserveRemoved(address token, uint256 amount);
    event PSMCollateralTransferred(address to, address token, uint256 amount);
    event PSMStatusChanged(address token, bool active);
    
    constructor(address _vcop, address _oracle) Ownable(msg.sender) {
        vcop = VCOPCollateralized(_vcop);
        oracle = VCOPOracle(_oracle);
        feeCollector = msg.sender;
    }
    
    /**
     * @dev Sets the PSM hook address
     */
    function setPSMHook(address _psmHook) external onlyOwner {
        require(_psmHook != address(0), "Zero address not allowed");
        psmHookAddress = _psmHook;
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
     * @dev Adds funds to PSM reserves
     * @param collateralToken Address of the collateral token
     * @param amount Amount of collateral to add to PSM reserves
     */
    function addPSMFunds(address collateralToken, uint256 amount) external onlyOwner {
        require(collaterals[collateralToken].active, "Collateral not active");
        require(amount > 0, "Amount must be greater than zero");
        
        // Transfer collateral to this contract
        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), amount);
        
        // Update PSM reserves
        psmReserves[collateralToken].collateralAmount += amount;
        psmReserves[collateralToken].active = true;
        
        emit PSMReserveAdded(collateralToken, amount);
    }
    
    /**
     * @dev Registers collateral funds already transferred to this contract as PSM reserves
     * @param collateralToken Address of the collateral token
     * @param amount Amount of collateral to register as PSM reserves
     */
    function registerPSMFunds(address collateralToken, uint256 amount) external {
        require(msg.sender == psmHookAddress, "Not authorized");
        require(collaterals[collateralToken].active, "Collateral not active");
        require(amount > 0, "Amount must be greater than zero");
        
        // Update PSM reserves (funds should already be transferred to this contract)
        psmReserves[collateralToken].collateralAmount += amount;
        psmReserves[collateralToken].active = true;
        
        // Update stats
        lastPSMOperationTimestamp = block.timestamp;
        
        emit PSMReserveAdded(collateralToken, amount);
    }
    
    /**
     * @dev Removes funds from PSM reserves
     * @param collateralToken Address of the collateral token
     * @param amount Amount of collateral to remove from PSM reserves
     */
    function removePSMFunds(address collateralToken, uint256 amount) external onlyOwner {
        PSMReserve storage reserve = psmReserves[collateralToken];
        require(reserve.active, "PSM reserve not active for token");
        require(amount <= reserve.collateralAmount, "Insufficient PSM reserves");
        
        // Update PSM reserves
        reserve.collateralAmount -= amount;
        
        // Transfer collateral to owner
        IERC20(collateralToken).safeTransfer(msg.sender, amount);
        
        emit PSMReserveRemoved(collateralToken, amount);
    }
    
    /**
     * @dev Sets PSM reserve active status
     * @param collateralToken Address of the collateral token
     * @param active Whether the PSM reserve should be active
     */
    function setPSMReserveStatus(address collateralToken, bool active) external onlyOwner {
        psmReserves[collateralToken].active = active;
        emit PSMStatusChanged(collateralToken, active);
    }
    
    /**
     * @dev Transfers collateral from PSM reserves (only callable by PSM hook)
     * @param to Address to receive the collateral
     * @param collateralToken Address of the collateral token
     * @param amount Amount of collateral to transfer
     */
    function transferPSMCollateral(address to, address collateralToken, uint256 amount) external {
        require(msg.sender == psmHookAddress, "Not authorized");
        PSMReserve storage reserve = psmReserves[collateralToken];
        require(reserve.active, "PSM reserve not active for token");
        require(reserve.collateralAmount >= amount, "Insufficient PSM reserves");
        
        // Update PSM reserves
        reserve.collateralAmount -= amount;
        
        // Update stats
        lastPSMOperationTimestamp = block.timestamp;
        totalPSMSwapsCount++;
        
        // Transfer collateral
        IERC20(collateralToken).safeTransfer(to, amount);
        
        emit PSMCollateralTransferred(to, collateralToken, amount);
    }
    
    /**
     * @dev Adds VCOP to PSM reserves (only callable by PSM hook)
     * @param collateralToken Associated collateral token for this VCOP
     * @param amount Amount of VCOP to add
     */
    function addPSMVcop(address collateralToken, uint256 amount) external {
        require(msg.sender == psmHookAddress, "Not authorized");
        PSMReserve storage reserve = psmReserves[collateralToken];
        require(reserve.active, "PSM reserve not active for token");
        
        // Update PSM reserves
        reserve.vcopAmount += amount;
        
        // Update stats
        lastPSMOperationTimestamp = block.timestamp;
    }
    
    /**
     * @dev Initializes VCOP in PSM reserves (only callable by owner during setup)
     * @param collateralToken Associated collateral token for this VCOP
     * @param amount Amount of VCOP to register
     */
    function initializePSMVcop(address collateralToken, uint256 amount) external onlyOwner {
        PSMReserve storage reserve = psmReserves[collateralToken];
        require(reserve.active, "PSM reserve not active for token");
        
        // Update PSM reserves
        reserve.vcopAmount += amount;
        
        // Update stats
        lastPSMOperationTimestamp = block.timestamp;
        
        emit PSMReserveAdded(collateralToken, amount);
    }
    
    /**
     * @dev Removes VCOP from PSM reserves and mints to recipient (only callable by PSM hook)
     * @param to Recipient of minted VCOP
     * @param collateralToken Associated collateral token for this VCOP
     * @param amount Amount of VCOP to mint
     */
    function mintPSMVcop(address to, address collateralToken, uint256 amount) external {
        require(msg.sender == psmHookAddress, "Not authorized");
        PSMReserve storage reserve = psmReserves[collateralToken];
        require(reserve.active, "PSM reserve not active for token");
        
        // Mint VCOP to recipient
        vcop.mint(to, amount);
        
        // Update stats
        lastPSMOperationTimestamp = block.timestamp;
    }
    
    /**
     * @dev Checks if PSM reserves are sufficient for a specific token and amount
     * @param collateralToken Address of the collateral token
     * @param amount Amount of collateral needed
     * @return Whether the reserves are sufficient
     */
    function hasPSMReservesFor(address collateralToken, uint256 amount) public view returns (bool) {
        PSMReserve memory reserve = psmReserves[collateralToken];
        return reserve.active && reserve.collateralAmount >= amount;
    }
    
    /**
     * @dev Gets PSM reserve statistics
     * @param collateralToken Address of the collateral token
     * @return collateralAmount Amount of collateral in the PSM
     * @return vcopAmount Amount of VCOP in the PSM
     * @return active Whether the PSM is active for this token
     */
    function getPSMReserves(address collateralToken) public view returns (
        uint256 collateralAmount,
        uint256 vcopAmount,
        bool active
    ) {
        PSMReserve memory reserve = psmReserves[collateralToken];
        return (reserve.collateralAmount, reserve.vcopAmount, reserve.active);
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