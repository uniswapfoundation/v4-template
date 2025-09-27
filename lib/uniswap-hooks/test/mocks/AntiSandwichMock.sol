// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "src/general/AntiSandwichHook.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {CurrencySettler} from "src/utils/CurrencySettler.sol";

contract AntiSandwichMock is AntiSandwichHook {
    using CurrencySettler for Currency;

    constructor(IPoolManager _poolManager) AntiSandwichHook(_poolManager) {}

    /**
     * @dev Handles the excess tokens collected during the swap due to the anti-sandwich mechanism.
     * When a swap executes at a worse price than what's currently available in the pool (due to
     * enforcing the beginning-of-block price), the excess tokens are donated back to the pool
     * to benefit all liquidity providers.
     *
     * WARNING: This example handles the accumulated anti-sandwich fees by donating the excess tokens to in-range
     * liquidity providers. Be aware that this type of donations may be vulnerable to JIT attacks. If this particular
     * type of handling is desired, consider combining with a JIT protection mechanism such as
     * https://github.com/OpenZeppelin/uniswap-hooks/blob/master/src/general/LiquidityPenaltyHook.sol[LiquidityPenaltyHook].
     */
    function _afterSwapHandler(
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta,
        uint256,
        uint256 feeAmount
    ) internal override {
        Currency unspecified = (params.amountSpecified < 0 == params.zeroForOne) ? (key.currency1) : (key.currency0);
        (uint256 amount0, uint256 amount1) = unspecified == key.currency0
            ? (uint256(uint128(feeAmount)), uint256(0))
            : (uint256(0), uint256(uint128(feeAmount)));

        // settle and donate execess tokens to the pool
        poolManager.donate(key, amount0, amount1, "");
        unspecified.settle(poolManager, address(this), feeAmount, true);
    }

    // Exclude from coverage report
    function test() public {}
}
