// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";

import { PathKey } from "./PathKey.sol";

/// @title Uniswap V4 Swap Router
/// @notice A simple, stateless router for execution of swaps against Uniswap v4 Pools
/// @dev ABI inspired by UniswapV2Router02; https://github.com/hookmate/v4-router
interface IUniswapV4Router04 {
    /// ================ MULTI POOL SWAPS ================= ///

    /// @notice Exact Input Swap; swap the specified amount of input tokens for as many output tokens as possible, along the path
    /// @param amountIn the amount of input tokens to swap
    /// @param amountOutMin the minimum amount of output tokens that must be received for the transaction not to revert. reverts on equals to
    /// @param startCurrency the currency to start the swap from
    /// @param path the path of v4 Pools to swap through
    /// @param receiver the address to send the output tokens to
    /// @param deadline block.timestamp must be before this value, otherwise the transaction will revert
    /// @return Delta the balance changes from the swap
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Currency startCurrency,
        PathKey[] calldata path,
        address receiver,
        uint256 deadline
    ) external payable returns (BalanceDelta);

    /// @notice Exact Output Swap; swap as few input tokens as possible for the specified amount of output tokens, along the path
    /// @param amountOut the amount of output tokens to receive
    /// @param amountInMax the maximum amount of input tokens that can be spent for the transaction not to revert. reverts on equal to
    /// @param startCurrency the currency to start the swap from
    /// @param path the path of v4 Pools to swap through
    /// @param receiver the address to send the output tokens to
    /// @param deadline block.timestamp must be before this value, otherwise the transaction will revert
    /// @return Delta the balance changes from the swap
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        Currency startCurrency,
        PathKey[] calldata path,
        address receiver,
        uint256 deadline
    ) external payable returns (BalanceDelta);

    /// @notice General-purpose swap interface for Uniswap v4 that handles all types of swaps
    /// @param amountSpecified the amount of tokens to be swapped, negative for exact input swaps and positive for exact output swaps
    /// @param amountLimit the minimum amount of output tokens for exact input swaps, the maximum amount of input tokens for exact output swaps
    /// @param startCurrency the currency to start the swap from
    /// @param path the path of v4 Pools to swap through
    /// @param receiver the address to send the output tokens to
    /// @param deadline block.timestamp must be before this value, otherwise the transaction will revert
    /// @return Delta the balance changes from the swap
    function swap(
        int256 amountSpecified,
        uint256 amountLimit,
        Currency startCurrency,
        PathKey[] calldata path,
        address receiver,
        uint256 deadline
    ) external payable returns (BalanceDelta);

    /// ================ SINGLE POOL SWAPS ================ ///

    /// @notice Single pool, exact input swap - swap the specified amount of input tokens for as many output tokens as possible, on a single pool
    /// @param amountIn the amount of input tokens to swap
    /// @param amountOutMin the minimum amount of output tokens that must be received for the transaction not to revert
    /// @param zeroForOne the direction of the swap, true if currency0 is being swapped for currency1
    /// @param poolKey the pool to swap through
    /// @param hookData the data to be passed to the hook
    /// @param receiver the address to send the output tokens to
    /// @param deadline block.timestamp must be before this value, otherwise the transaction will revert
    /// @return Delta the balance changes from the swap
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        bool zeroForOne,
        PoolKey calldata poolKey,
        bytes calldata hookData,
        address receiver,
        uint256 deadline
    ) external payable returns (BalanceDelta);

    /// @notice Singe pool, exact output swap; swap as few input tokens as possible for the specified amount of output tokens, on a single pool
    /// @param amountOut the amount of output tokens to receive
    /// @param amountInMax the maximum amount of input tokens that can be spent for the transaction not to revert
    /// @param zeroForOne the direction of the swap, true if currency0 is being swapped for currency1
    /// @param poolKey the pool to swap through
    /// @param hookData the data to be passed to the hook
    /// @param receiver the address to send the output tokens to
    /// @param deadline block.timestamp must be before this value, otherwise the transaction will revert
    /// @return Delta the balance changes from the swap
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        bool zeroForOne,
        PoolKey calldata poolKey,
        bytes calldata hookData,
        address receiver,
        uint256 deadline
    ) external payable returns (BalanceDelta);

    /// @notice General-purpose single-pool swap interface
    /// @param amountSpecified the amount of tokens to be swapped, negative for exact input swaps and positive for exact output swaps
    /// @param amountLimit the minimum amount of output tokens for exact input swaps, the maximum amount of input tokens for exact output swaps
    /// @param zeroForOne the direction of the swap, true if currency0 is being swapped for currency1
    /// @param poolKey the pool to swap through
    /// @param hookData the data to be passed to the hook
    /// @param receiver the address to send the output tokens to
    /// @param deadline block.timestamp must be before this value, otherwise the transaction will revert
    /// @return Delta the balance changes from the swap
    function swap(
        int256 amountSpecified,
        uint256 amountLimit,
        bool zeroForOne,
        PoolKey calldata poolKey,
        bytes calldata hookData,
        address receiver,
        uint256 deadline
    ) external payable returns (BalanceDelta);

    /// ================ OPTIMIZED ================ ///

    /// @notice Generic multi-pool swap function that accepts pre-encoded calldata
    /// @dev Minor optimization to reduce the number of onchain abi.encode calls
    /// @param data Pre-encoded swap data in one of the following formats:
    ///     1. For single-pool swaps: abi.encode(
    ///         BaseData baseData,             // struct containing swap parameters
    ///         bool zeroForOne,               // direction of swap
    ///         PoolKey poolKey,               // key of the pool to swap through
    ///         bytes hookData                 // data to pass to hooks
    ///     )
    ///     2. For multi-pool swaps: abi.encode(
    ///         BaseData baseData,             // struct containing swap parameters
    ///         Currency startCurrency,        // initial currency in the swap
    ///         PathKey[] path                 // array of path keys defining the route
    ///     )
    ///
    ///     PERMIT2 EXTENSION:
    ///     1. For single pool swaps: abi.encode(
    ///         BaseData baseData,             // struct containing swap parameters
    ///         bool zeroForOne,               // direction of swap
    ///         PoolKey poolKey,               // key of the pool to swap through
    ///         bytes hookData,                // data to pass to hooks
    ///         PermitPayload permitPayload    // permit2 signature payload
    ///     )
    ///     2. For multi-pool swaps: abi.encode(
    ///         BaseData baseData,             // struct containing swap parameters
    ///         Currency startCurrency,        // initial currency in the swap
    ///         PathKey[] path,                // array of path keys defining the route
    ///         PermitPayload permitPayload    // permit2 signature payload
    ///     )
    ///     Where BaseData.flags contains permit2 flag, and PermitPayload contains:
    ///         - permit: ISignatureTransfer.PermitTransferFrom
    ///         - signature: bytes
    ///
    /// @param deadline block.timestamp must be before this value, otherwise the transaction will revert
    /// @return Delta the balance changes from the swap
    function swap(bytes calldata data, uint256 deadline) external payable returns (BalanceDelta);

    /// @notice Provides ETH receipts locked to Pool Manager
    receive() external payable;

    /// ================ GETTERS ================ ///

    /// @notice Public view function to be used instead of msg.sender, as the contract performs self-reentrancy and at
    /// times msg.sender == address(this). Instead msgSender() returns the initiator of the lock
    function msgSender() external view returns (address);
}
