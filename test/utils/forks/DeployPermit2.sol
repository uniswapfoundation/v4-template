// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {CommonBase} from "forge-std/Base.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

import {Permit2Bytecode} from "./Permit2Bytecode.sol";

/// @notice helper to deploy permit2 from precompiled bytecode. To be used in foundry tests and scripts
/// @dev useful if testing externally against permit2 and want to avoid
/// recompiling entirely and requiring viaIR compilation
/// a fork of DeployPermit2 from the permit2 repository
contract DeployPermit2 is CommonBase, Permit2Bytecode {
    IAllowanceTransfer permit2 = IAllowanceTransfer(address(0x000000000022D473030F116dDEE9F6B43aC78BA3));

    /// @notice Deploys permit2 with vm.etch, to be used in foundry tests
    function etchPermit2() public returns (IAllowanceTransfer) {
        vm.etch(address(permit2), PERMIT2_BYTECODE);
        return permit2;
    }

    /// @notice Deploys permit2 with anvil_setCode, to be used in foundry scripts against anvil
    function anvilPermit2() public returns (IAllowanceTransfer) {
        vm.rpc(
            "anvil_setCode",
            string.concat('["', vm.toString(address(permit2)), '","', vm.toString(PERMIT2_BYTECODE), '"]')
        );
        return permit2;
    }
}
