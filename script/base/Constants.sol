// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

/// @notice Shared constants used in scripts
contract Constants {
    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    /// @dev populated with default anvil addresses
    IPoolManager constant POOLMANAGER = IPoolManager(address(0x5FbDB2315678afecb367f032d93F642f64180aa3));
    PositionManager constant posm = PositionManager(payable(address(0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0)));
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(address(0x000000000022D473030F116dDEE9F6B43aC78BA3));
}
