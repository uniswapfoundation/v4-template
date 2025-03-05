// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {HookMetadata} from "v4-periphery/src/utils/HookMetadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EIP712_v4} from "v4-periphery/src/base/EIP712_v4.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";

contract Counter is BaseHook, HookMetadata, EIP712_v4, Ownable {
    using PoolIdLibrary for PoolKey;

    // NOTE: ---------------------------------------------------------
    // state variables should typically be unique to a pool
    // a single hook contract should be able to service multiple pools
    // ---------------------------------------------------------------

    mapping(PoolId => uint256 count) public beforeSwapCount;
    mapping(PoolId => uint256 count) public afterSwapCount;

    mapping(PoolId => uint256 count) public beforeAddLiquidityCount;
    mapping(PoolId => uint256 count) public beforeRemoveLiquidityCount;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) EIP712_v4("Counter") Ownable(msg.sender) {}

    /// @notice Registers an audit summary signed by a trusted auditor. Only the owner can call this function.
    /// @dev This function is only for demonstration purposes. It may have different signature and logic in a real
    ///      implementation (for example, it may be controlled by a DAO). However, it should call `_registerAuditSummary`
    ///      function to store the audit summary and emit an event needed for external indexing services.
    /// @param _signedAuditSummary The signed audit summary.
    /// @return The audit summary's ID.
    function registerAuditSummary(SignedAuditSummary memory _signedAuditSummary) external onlyOwner returns (uint256) {
        return _registerAuditSummary(_signedAuditSummary);
    }

    /// @notice Returns the name of the hook.
    /// @return The hook's name as a string.
    function name() external pure override returns (string memory) {
        return "Counter";
    }

    /// @notice Returns the repository URI for the hook's source code.
    /// @return The repository URI.
    function repositoryURI() external pure override returns (string memory) {
        return "Hook's repository URI";
    }

    /// @notice Returns the URI for the hook's logo.
    /// @return The logo URI.
    function logoURI() external pure override returns (string memory) {
        return "Hook's logo URI";
    }

    /// @notice Returns the URI for the hook's website.
    /// @return The website URI.
    function websiteURI() external pure override returns (string memory) {
        return "Hook's website URI";
    }

    /// @notice Returns a description of the hook.
    /// @return The hook's description.
    function description() external pure override returns (string memory) {
        return "Counter hook with metadata which might be useful for external indexing services.";
    }

    /// @notice Returns the version of the hook.
    /// @return The version identifier as bytes32.
    function version() external pure override returns (bytes32) {
        return "1.0";
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // -----------------------------------------------
    // NOTE: see IHooks.sol for function documentation
    // -----------------------------------------------

    function _beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        beforeSwapCount[key.toId()]++;
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        afterSwapCount[key.toId()]++;
        return (BaseHook.afterSwap.selector, 0);
    }

    function _beforeAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) internal override returns (bytes4) {
        beforeAddLiquidityCount[key.toId()]++;
        return BaseHook.beforeAddLiquidity.selector;
    }

    function _beforeRemoveLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) internal override returns (bytes4) {
        beforeRemoveLiquidityCount[key.toId()]++;
        return BaseHook.beforeRemoveLiquidity.selector;
    }
}
