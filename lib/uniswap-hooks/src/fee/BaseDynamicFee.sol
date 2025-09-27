// SPDX-License-Identifier: MIT
// OpenZeppelin Uniswap Hooks (last updated v0.1.0) (src/fee/BaseDynamicFee.sol)

pragma solidity ^0.8.24;

import {BaseHook} from "src/base/BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";

/**
 * @dev Base implementation to apply a dynamic fee via the `PoolManager`'s `updateDynamicLPFee` function.
 *
 * WARNING: This is experimental software and is provided on an "as is" and "as available" basis. We do
 * not give any warranties and will not be liable for any losses incurred through any use of this code
 * base.
 *
 * _Available since v0.1.0_
 */
abstract contract BaseDynamicFee is BaseHook {
    using LPFeeLibrary for uint24;

    /**
     * @dev The hook was attempted to be initialized with a non-dynamic fee.
     */
    error NotDynamicFee();

    /**
     * @dev Set the `PoolManager` address.
     */
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    /**
     * @dev Returns a fee, denominated in hundredths of a bip, to be applied to the pool after it is initialized.
     */
    function _getFee(PoolKey calldata key) internal virtual returns (uint24);

    /**
     * @dev Set the fee after the pool is initialized.
     */
    function _afterInitialize(address, PoolKey calldata key, uint160, int24)
        internal
        virtual
        override
        returns (bytes4)
    {
        if (!key.fee.isDynamicFee()) revert NotDynamicFee();
        poolManager.updateDynamicLPFee(key, _getFee(key));
        return this.afterInitialize.selector;
    }

    /**
     * @dev Updates the dynamic LP fee for the given pool, which must have a key
     * that contains this hook's address.
     *
     * WARNING: This function can be called by anyone at any time. If `_getFee` implementation
     * depends on external conditions (e.g., oracle prices, other pool states, token balances),
     * it may be vulnerable to manipulation. An attacker could potentially:
     * 1. Manipulate the external conditions that `_getFee` depends on
     * 2. Call `poke()` to update the fee to a more favorable rate
     * 3. Execute trades at the manipulated fee rate
     *
     * Inheriting contracts should consider implementing access controls on this function,
     * make the logic in `_getFee` resistant to short-term manipulation, or accept the risk
     * of fee manipulation.
     *
     * @param key The pool key to update the dynamic LP fee for.
     */
    function poke(PoolKey calldata key) external virtual onlyValidPools(key.hooks) {
        poolManager.updateDynamicLPFee(key, _getFee(key));
    }

    /**
     * @dev Set the hook permissions, specifically `afterInitialize`.
     *
     * @return permissions The hook permissions.
     */
    function getHookPermissions() public pure virtual override returns (Hooks.Permissions memory permissions) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
}
