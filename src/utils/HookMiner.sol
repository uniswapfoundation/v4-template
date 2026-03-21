// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice HookMiner - a utility for mining hook addresses with desired permissions flags.
/// @dev Originally from @uniswap/v4-periphery, recreated locally as it was removed from the latest periphery.
library HookMiner {
    // mask to filter out bits that are not part of the flags
    uint160 constant FLAG_MASK = 0x3fff;

    /// @notice Mines a hook address with the desired flags
    /// @param deployer the address that will deploy the hook
    /// @param flags the desired permission flags
    /// @param creationCode the creation code of the hook contract
    /// @param constructorArgs the constructor arguments
    /// @return hookAddress the computed hook address
    /// @return salt the salt to use with CREATE2
    function find(address deployer, uint160 flags, bytes memory creationCode, bytes memory constructorArgs)
        internal
        pure
        returns (address hookAddress, bytes32 salt)
    {
        bytes32 creationCodeHash = keccak256(abi.encodePacked(creationCode, constructorArgs));
        
        for (uint256 i = 0; i < 100_000; i++) {
            salt = bytes32(i);
            hookAddress = computeAddress(deployer, salt, creationCodeHash);
            
            if (uint160(hookAddress) & FLAG_MASK == flags) {
                return (hookAddress, salt);
            }
        }
        revert("HookMiner: could not find salt");
    }

    /// @notice Computes the CREATE2 address
    function computeAddress(address deployer, bytes32 salt, bytes32 creationCodeHash) 
        internal 
        pure 
        returns (address) 
    {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, creationCodeHash)))));
    }
}
