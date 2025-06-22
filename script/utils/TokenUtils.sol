// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @dev Library for common token/utility operations.
library TokenUtils {
    /// @dev Numerically sort token addresses
    function sortTokens(IERC20 token0, IERC20 token1) public pure returns (IERC20, IERC20) {
        address token0addr = address(token0);
        address token1addr = address(token1);
        require(token0addr != token1addr, "Token addresses must not match.");

        return uint160(token0addr) < uint160(token1addr) ? (token0, token1) : (token1, token0);
    }

    /// @dev Attempts to obtain a descriptive label/symbol for a token
    function getTokenLabel(IERC20 _token) public view returns (string memory) {
        // 0 address won't revert in try/catch
        if (address(_token) == address(0)) {
            return "ETH";
        }

        try _token.symbol() returns (string memory symbol) {
            return string.concat("(", symbol, ")");
        } catch {
            return string.concat("(No Symbol)");
        }
    }
}
