// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockUSDC is ERC20, ERC20Burnable, Ownable {
    constructor() ERC20("USD Coin (Mock)", "USDC") Ownable(msg.sender) {}

    /// @notice Mint USDC (6 decimals) to an address. Owner only.
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /// @dev Override to 6 decimals to match real USDC.
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}