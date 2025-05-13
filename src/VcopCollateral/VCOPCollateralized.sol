// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "v4-core/lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {console2 as console} from "forge-std/console2.sol";

/**
 * @title VCOPCollateralized
 * @notice Implementation of a collateral-backed stablecoin pegged to the Colombian Peso (COP)
 * @dev This token has 6 decimals to maintain compatibility with USDC
 */
contract VCOPCollateralized is ERC20, Ownable {
    // Collateral manager contract
    address public collateralManager;
    
    // Minting/burning permissions
    mapping(address => bool) public minters;
    mapping(address => bool) public burners;
    
    // Events
    event MinterUpdated(address account, bool status);
    event BurnerUpdated(address account, bool status);
    event CollateralManagerUpdated(address oldManager, address newManager);

    constructor() ERC20("VCOP Stablecoin", "VCOP") Ownable(msg.sender) {
        minters[msg.sender] = true;
        burners[msg.sender] = true;
    }
    
    /**
     * @dev Returns 6 decimals instead of ERC20 default 18
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }
    
    /**
     * @dev Sets the collateral manager contract
     */
    function setCollateralManager(address _manager) external onlyOwner {
        require(_manager != address(0), "Zero address not allowed");
        address oldManager = collateralManager;
        collateralManager = _manager;
        emit CollateralManagerUpdated(oldManager, _manager);
    }
    
    /**
     * @dev Updates minter privileges
     */
    function setMinter(address account, bool status) external onlyOwner {
        minters[account] = status;
        emit MinterUpdated(account, status);
    }
    
    /**
     * @dev Updates burner privileges
     */
    function setBurner(address account, bool status) external onlyOwner {
        burners[account] = status;
        emit BurnerUpdated(account, status);
    }
    
    /**
     * @dev Mints new tokens (only by authorized minters)
     */
    function mint(address to, uint256 amount) external {
        require(minters[msg.sender], "Not authorized to mint");
        _mint(to, amount);
    }
    
    /**
     * @dev Burns tokens (only by authorized burners)
     */
    function burn(address from, uint256 amount) external {
        require(burners[msg.sender], "Not authorized to burn");
        _burn(from, amount);
    }
}