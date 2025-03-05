// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {HookMetadata} from "v4-periphery/src/utils/HookMetadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {EIP712_v4} from "v4-periphery/src/base/EIP712_v4.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PointsToken} from "./mock/PointsToken.sol";

/**
 * @title PointsHookWithMetadata
 * @notice A basic hook implementation which shows how to setup a hook with metadata for external indexing services. This
 *         hook is based on Uniswap's PointsHook: https://docs.uniswap.org/contracts/v4/guides/hooks/your-first-hook
 */
contract PointsHookWithMetadata is BaseHook, HookMetadata, EIP712_v4, Ownable {
    PointsToken public pointsToken;

    /// @notice Constructor which initializes the hook and the points token.
    /// @param _poolManager The Uniswap's V4 PoolManager contract address.
    constructor(IPoolManager _poolManager)
        BaseHook(_poolManager)
        EIP712_v4("PointsHookWithMetadata")
        Ownable(msg.sender)
    {
        pointsToken = new PointsToken();
    }

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
        return "PointsHookWithMetadata";
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
        return "Points hook with metadata which might be useful for external indexing services.";
    }

    /// @notice Returns the version of the hook.
    /// @return The version identifier as bytes32.
    function version() external pure override returns (bytes32) {
        return "1.0";
    }

    /// @notice Returns a struct of permissions to signal which hook functions are to be implemented. It will also be
    ///         used at deployment to validate the address correctly represents the expected permissions.
    /// @return The hook's permissions.
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @notice Returns the encoded data to be passed to the hook at the time of invocation.
    /// @param _user The address of the user to award points to.
    /// @return The encoded data to be passed to the hook.
    function getHookData(address _user) public pure returns (bytes memory) {
        return abi.encode(_user);
    }

    /// @notice Decodes the data passed to the hook at the time of invocation.
    /// @param _data The encoded data passed to the hook.
    /// @return The address of the user to award points to.
    function parseHookData(bytes calldata _data) public pure returns (address) {
        return abi.decode(_data, (address));
    }

    /// @notice Hook function called after a swap has occurred.
    /// @param _key The pool key of the pool where the swap occurred.
    /// @param _swapParams The swap parameters.
    /// @param _delta The balance delta of the pool after the swap.
    /// @param _hookData The encoded data passed to the hook.
    /// @return The selector of the hook and the delta of the balance.
    function _afterSwap(
        address,
        PoolKey calldata _key,
        IPoolManager.SwapParams calldata _swapParams,
        BalanceDelta _delta,
        bytes calldata _hookData
    ) internal override returns (bytes4, int128) {
        if (_key.currency0.isAddressZero() && _swapParams.zeroForOne) {
            awardPoints(
                parseHookData(_hookData),
                _swapParams.amountSpecified < 0
                    ? uint256(-_swapParams.amountSpecified)
                    : uint256(int256(-_delta.amount0()))
            );
        }

        return (BaseHook.afterSwap.selector, 0);
    }

    /// @notice Hook function called after liquidity has been added to a pool.
    /// @param _key The pool key of the pool where the liquidity was added.
    /// @param _delta The balance delta of the pool after the liquidity addition.
    /// @param _hookData The encoded data passed to the hook.
    /// @return The selector of the hook and the delta of the balance.
    function _afterAddLiquidity(
        address,
        PoolKey calldata _key,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta _delta,
        BalanceDelta,
        bytes calldata _hookData
    ) internal override returns (bytes4, BalanceDelta) {
        if (_key.currency0.isAddressZero()) {
            awardPoints(parseHookData(_hookData), uint256(int256(-_delta.amount0())));
        }

        return (BaseHook.afterAddLiquidity.selector, _delta);
    }

    /// @notice Awards points to a user by minting them to the user's address.
    /// @param _to The address of the user to award points to.
    /// @param _amount The amount of points to award.
    function awardPoints(address _to, uint256 _amount) internal {
        pointsToken.mint(_to, _amount);
    }
}
