// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Constants used across scripts
library Constants {
    /// @notice The CREATE2 factory address used for deterministic deployments
    address internal constant CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    
    /// @notice PoolManager address for Unichain Sepolia (chain ID 1301)
    address internal constant POOL_MANAGER = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
    
    /// @notice PositionManager address for Unichain Sepolia (chain ID 1301)
    address internal constant POSITION_MANAGER = 0xf969Aee60879C54bAAed9F3eD26147Db216Fd664;

    /// @notice PositionManager address for Unichain Sepolia (chain ID 1301)
    address internal constant UNISWAP_ROUTER = 0xdE960C7dcd629916b6618E2B7E4B4413a532550b;
}