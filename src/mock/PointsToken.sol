// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";

/**
 * @title PointsToken
 * @notice A simple ERC20 token which can be minted by the owner and is used in the PointsHookWithMetadata contract.
 */
contract PointsToken is ERC20, Ownable {
    /// @notice A constructor which sets the name and symbol of the token and makes the deployer the owner.
    constructor() ERC20("Points Token", "POINTS") Ownable(msg.sender) {}

    /// @notice Mints `_amount` of tokens to `_to`. Caller must be the owner.
    /// @param _to The address to mint tokens to.
    /// @param _amount The amount of tokens to mint.
    function mint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
    }
}
