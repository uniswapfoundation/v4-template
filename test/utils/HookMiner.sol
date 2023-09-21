// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title HookMiner - a library for deploying Uni V4 hooks with target flags
library HookMiner {
    uint160 constant UNISWAP_FLAG_MASK = 0xff << 152;

    function mineSalt(address deployer, uint160 targetFlags, bytes memory creationCode)
        external
        pure
        returns (address hook, uint256 salt)
    {
        uint160 prefix = 1;
        for (salt; salt < 1000;) {
            hook = computeAddress(deployer, salt, creationCode);
            prefix = uint160(hook) & UNISWAP_FLAG_MASK;
            if (prefix == targetFlags) {
                break;
            }

            unchecked {
                ++salt;
            }
        }
        require(uint160(hook) & UNISWAP_FLAG_MASK == targetFlags, "HookMiner: could not find hook address");
    }

    /// @notice Precompute a contract address deployed via CREATE2
    function computeAddress(address deployer, uint256 salt, bytes memory creationCode) public pure returns (address) {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, keccak256(creationCode)))))
        );
    }
}
