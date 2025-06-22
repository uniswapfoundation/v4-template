// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

/// @dev Deploy mock tokens for local testing.
library DeployToken {
    function run(string memory name, string memory symbol, uint256 supply, address deployer)
        internal
        returns (IERC20 token)
    {
        MockERC20 mockToken = new MockERC20(name, symbol, 18);
        mockToken.mint(deployer, supply);

        token = IERC20(address(mockToken));
    }
}
