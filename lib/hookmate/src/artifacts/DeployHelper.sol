//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library DeployHelper {
    function deploy(bytes memory initcode, bytes32 salt) internal returns (address contractAddress) {
        assembly ("memory-safe") {
            contractAddress := create2(0, add(initcode, 32), mload(initcode), salt)
            if iszero(contractAddress) {
                let ptr := mload(0x40)
                let errorSize := returndatasize()
                returndatacopy(ptr, 0, errorSize)
                revert(ptr, errorSize)
            }
        }
    }

    function deploy(bytes memory initcode) internal returns (address contractAddress) {
        return deploy(initcode, hex"00");
    }
}
