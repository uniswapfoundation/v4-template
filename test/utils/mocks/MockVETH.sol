// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockVETH is ERC20, ERC20Burnable, Ownable {
    constructor() ERC20("Virtual Ether", "vETH") Ownable(msg.sender) {}

    /// @notice Mint vETH (18 decimals) to an address. Owner only.
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
    // decimals() defaults to 18 via ERC20
}