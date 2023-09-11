// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title HookDeployer - a library for deploying Uni V4 hooks with target flags
/// @notice - This library assumes Arachnid's deterministic deployment proxy is available at 0x4e59b44847b379578588920cA78FbF26c0B4956C
///           (true for anvil and most testnets)
library HookDeployer {
    // Arachnid's deterministic deployment proxy
    // provided by anvil, by default
    // https://github.com/Arachnid/deterministic-deployment-proxy
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    uint160 constant UNISWAP_FLAG_MASK = 0xff << 152;

    function deploy(uint160 targetFlags, bytes memory creationCode) external returns (address) {
        (, uint256 salt) = mineSalt(targetFlags, creationCode);
        return deployWithSalt(creationCode, salt);
    }

    function deployWithSalt(bytes memory creationCode, uint256 salt) public returns (address) {
        // Deploy the hook using the CREATE2 Deployer Proxy (provided by anvil)
        (bool success,) = address(CREATE2_DEPLOYER).call(abi.encodePacked(salt, creationCode));
        require(success, "HookDeployer: could not deploy hook");
        return _getAddress(salt, creationCode);
    }

    function mineSalt(uint160 targetFlags, bytes memory creationCode)
        internal
        pure
        returns (address hook, uint256 salt)
    {
        uint160 prefix = 1;
        for (salt; salt < 1000;) {
            hook = _getAddress(salt, creationCode);
            prefix = uint160(hook) & UNISWAP_FLAG_MASK;
            if (prefix == targetFlags) {
                break;
            }

            unchecked {
                ++salt;
            }
        }
        require(uint160(hook) & UNISWAP_FLAG_MASK == targetFlags, "HookDeployer: could not find hook address");
    }

    /// @notice Precompute a contract address that is deployed with the CREATE2Deployer
    function _getAddress(uint256 salt, bytes memory creationCode) internal pure returns (address) {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), CREATE2_DEPLOYER, salt, keccak256(creationCode)))))
        );
    }
}
