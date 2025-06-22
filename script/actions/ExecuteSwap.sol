// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IUniswapV4Router04} from "hookmate/interfaces/router/IUniswapV4Router04.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {TokenApprover} from "../utils/TokenApprover.sol";
import {PoolInputs, CurrencyPair} from "../types/Types.sol";

/// @dev Swap tokens
library ExecuteSwap {
    function run(
        IPermit2 permit2,
        IUniswapV4Router04 router,
        CurrencyPair memory currencyPair,
        IHooks hooks,
        PoolInputs memory poolInputs,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 deadline,
        bytes memory hookData,
        address deployer
    ) internal {
        require(
            Currency.unwrap(currencyPair.currency0) != Currency.unwrap(currencyPair.currency1),
            "Token addresses should not match."
        );
        require(
            uint160(Currency.unwrap(currencyPair.currency0)) < uint160(Currency.unwrap(currencyPair.currency1)),
            "Token addresses should be numerically sorted."
        );

        PoolKey memory poolKey =
            PoolKey(currencyPair.currency0, currencyPair.currency1, poolInputs.lpFee, poolInputs.tickSpacing, hooks);

        // Permit2 is not respected here?
        // TokenApprover.approveUnlimited(permit2, currencyPair.currency0, address(router));
        IERC20(Currency.unwrap(currencyPair.currency0)).approve(address(router), type(uint256).max);
        router.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: amountOutMin,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: hookData,
            receiver: deployer,
            deadline: deadline
        });
    }
}
