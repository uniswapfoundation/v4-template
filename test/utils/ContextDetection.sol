// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.21;

/// @title Foundry Context Detection
/// @notice A helper library to discern what environment we are in without having to pass the vm object.
/// @dev Intended for use within EasyPosm due to context issues of address(this) in scripting vs test environments.
library ContextDetection {
    /// @dev ref: https://getfoundry.sh/forge/tests/cheatcodes/
    address constant VM_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

    /// @dev ref: https://getfoundry.sh/reference/cheatcodes/is-context#examples
    uint8 constant CONTEXT_TEST_GROUP = 0; // VmSafe.ForgeContext.TestGroup

    /// @dev Determines whether we're running in the ctx/environment of a foundry test
    function isTest() internal view returns (bool result) {
        // vm.isContext() selector
        bytes4 selector = bytes4(keccak256("isContext(uint8)"));

        assembly {
            // 4 (selector) + 32 (arg)
            let ptr := mload(0x40)
            mstore(ptr, selector)
            mstore(add(ptr, 0x04), CONTEXT_TEST_GROUP)

            // vm.isContext(CONTEXT_TEST_GROUP)
            let success := staticcall(gas(), VM_ADDRESS, ptr, 0x24, ptr, 0x20)
            // success should simply be false in mainnet, so result = false
            if success { result := mload(ptr) }
        }
    }
}
