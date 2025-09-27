// SPDX-License-Identifier: MIT
// OpenZeppelin Uniswap Hooks (last updated v0.1.0) (src/utils/CurrencySettler.sol)

pragma solidity ^0.8.24;

import {Currency} from "v4-core/src/types/Currency.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

/**
 * @dev Library used to interact with the `PoolManager` to settle any open deltas.
 * To settle a positive delta (a credit to the user), a user may take or mint.
 * To settle a negative delta (a debt on the user), a user may transfer or burn to pay off a debt.
 *
 * Based on the https://github.com/Uniswap/v4-core/blob/main/test/utils/CurrencySettler.sol[Uniswap v4 test utils implementation].
 *
 * NOTE: Deltas are synced before any ERC-20 transfers in {settle} function.
 */
library CurrencySettler {
    using SafeERC20 for IERC20;

    /**
     * @notice Settle (pay) a currency to the `PoolManager`
     * @param currency Currency to settle
     * @param poolManager `PoolManager` to settle to
     * @param payer Address of the payer, which can be the hook itself or an external address.
     * @param amount Amount to send
     * @param burn If true, burn the ERC-6909 token, otherwise transfer ERC-20 to the `PoolManager`
     */
    function settle(Currency currency, IPoolManager poolManager, address payer, uint256 amount, bool burn) internal {
        // Early return when amount is 0 given that some tokens may revert in this case
        if (amount == 0) return;

        // For native currencies or burns, calling sync is not required
        // Short circuit for ERC-6909 burns to support ERC-6909-wrapped native tokens
        if (burn) {
            poolManager.burn(payer, currency.toId(), amount);
        } else if (currency.isAddressZero()) {
            poolManager.sync(currency);
            poolManager.settle{value: amount}();
        } else {
            poolManager.sync(currency);
            if (payer != address(this)) {
                IERC20(Currency.unwrap(currency)).safeTransferFrom(payer, address(poolManager), amount);
            } else {
                IERC20(Currency.unwrap(currency)).safeTransfer(address(poolManager), amount);
            }
            poolManager.settle();
        }
    }

    /**
     * @notice Take (receive) a currency from the `PoolManager`
     * @param currency Currency to take
     * @param poolManager `PoolManager` to take from
     * @param recipient Address of the recipient of the ERC-6909 or ERC-20 token.
     * @param amount Amount to receive
     * @param claims If true, mint the ERC-6909 token, otherwise transfer ERC-20 from the `PoolManager` to recipient
     */
    function take(Currency currency, IPoolManager poolManager, address recipient, uint256 amount, bool claims)
        internal
    {
        // Early return when amount is 0 given that some tokens may revert in this case
        if (amount == 0) return;

        claims ? poolManager.mint(recipient, currency.toId(), amount) : poolManager.take(currency, recipient, amount);
    }
}
