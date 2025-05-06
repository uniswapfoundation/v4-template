//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {PoolManagerAddresses} from "./PoolManagerAddresses.sol";
import {PositionManagerAddresses} from "./PositionManagerAddresses.sol";

/// @notice Shared constants used in scripts
contract Constants {
    using PoolManagerAddresses for uint256;
    using PositionManagerAddresses for uint256;

    IPoolManager immutable POOLMANAGER;
    PositionManager immutable posm;

    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(address(0x000000000022D473030F116dDEE9F6B43aC78BA3));

    constructor() {
        POOLMANAGER = IPoolManager(block.chainid.getPoolManagerByChainId());
        posm = PositionManager(payable(block.chainid.getPositionManagerByChainId()));
    }
}
