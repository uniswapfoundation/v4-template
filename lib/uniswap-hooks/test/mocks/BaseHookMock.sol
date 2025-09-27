// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "src/base/BaseHook.sol";

import {BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";

contract BaseHookMock is BaseHook {
    event BeforeInitialize();
    event AfterInitialize();
    event BeforeAddLiquidity();
    event BeforeRemoveLiquidity();
    event AfterAddLiquidity();
    event AfterRemoveLiquidity();
    event BeforeSwap();
    event AfterSwap();
    event BeforeDonate();
    event AfterDonate();
    event Callback();

    error RevertCallback();

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function _beforeInitialize(address, PoolKey calldata, uint160) internal virtual override returns (bytes4) {
        emit BeforeInitialize();
        return this.beforeInitialize.selector;
    }

    function _afterInitialize(address, PoolKey calldata, uint160, int24) internal virtual override returns (bytes4) {
        emit AfterInitialize();
        return this.afterInitialize.selector;
    }

    function _beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        internal
        virtual
        override
        returns (bytes4)
    {
        emit BeforeAddLiquidity();
        return this.beforeAddLiquidity.selector;
    }

    function _beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        internal
        virtual
        override
        returns (bytes4)
    {
        emit BeforeRemoveLiquidity();
        return this.beforeRemoveLiquidity.selector;
    }

    function _afterAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal virtual override returns (bytes4, BalanceDelta) {
        emit AfterAddLiquidity();
        return (this.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function _afterRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal virtual override returns (bytes4, BalanceDelta) {
        emit AfterRemoveLiquidity();
        return (this.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata, bytes calldata)
        internal
        virtual
        override
        onlyValidPools(key.hooks)
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        emit BeforeSwap();
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        virtual
        override
        returns (bytes4, int128)
    {
        emit AfterSwap();
        return (this.afterSwap.selector, 0);
    }

    function _beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        internal
        virtual
        override
        returns (bytes4)
    {
        emit BeforeDonate();
        return this.beforeDonate.selector;
    }

    function _afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        internal
        virtual
        override
        returns (bytes4)
    {
        emit AfterDonate();
        return this.afterDonate.selector;
    }

    /**
     * @dev Set all permissions.
     */
    function getHookPermissions() public pure virtual override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: true,
            beforeAddLiquidity: true,
            beforeRemoveLiquidity: true,
            afterAddLiquidity: true,
            afterRemoveLiquidity: true,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: true,
            afterDonate: true,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function callback(bytes memory call) external {
        poolManager.unlock(call);
    }

    function unlockCallback(bytes calldata rawData) external onlyPoolManager returns (bytes memory) {
        (bool success, bytes memory returnData) = address(this).call(rawData);
        if (success) return returnData;
        // if the call failed, bubble up the reason
        assembly ("memory-safe") {
            revert(add(returnData, 32), mload(returnData))
        }
    }

    /// @dev when called in the `callback` function, the poolManager will call the `_unlockCallback` function which calls this contract's `_callback` function itself.
    function _callback(bool revertCallback) external onlySelf returns (bytes memory) {
        emit Callback();
        if (revertCallback) revert RevertCallback();
        return bytes("");
    }

    // Exclude from coverage report
    function test() public {}
}

contract BaseHookMockReverts is BaseHook {
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    /**
     * @dev Set all permissions.
     */
    function getHookPermissions() public pure virtual override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: true,
            beforeAddLiquidity: true,
            beforeRemoveLiquidity: true,
            afterAddLiquidity: true,
            afterRemoveLiquidity: true,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: true,
            afterDonate: true,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // Exclude from coverage report
    function test() public {}
}
