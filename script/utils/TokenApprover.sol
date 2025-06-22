// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

/// @dev Grants both permit2 approval and standard ERC20 approval.
library TokenApprover {
    /// @dev Gives unlimited approval of {currency} to {toBeApproved} address
    function approveUnlimited(IPermit2 p2, Currency currency, address toBeApproved) internal {
        if (currency.isAddressZero()) return;

        IERC20(Currency.unwrap(currency)).approve(address(p2), type(uint256).max);
        p2.approve(Currency.unwrap(currency), toBeApproved, type(uint160).max, type(uint48).max);
    }
}
