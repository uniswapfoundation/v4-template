// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {PoolManager} from "@uniswap/v4-core/contracts/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolModifyPositionTest} from "@uniswap/v4-core/contracts/test/PoolModifyPositionTest.sol";
import {PoolSwapTest} from "@uniswap/v4-core/contracts/test/PoolSwapTest.sol";
import {PoolDonateTest} from "@uniswap/v4-core/contracts/test/PoolDonateTest.sol";
import {Counter} from "../src/Counter.sol";
import {CounterImplementation} from "../test/implementation/CounterImplementation.sol";

/// @notice Forge script for deploying v4 & hooks to **anvil**
/// @dev This script only works on an anvil RPC because v4 exceeds bytecode limits
/// @dev and we also need vm.etch() to deploy the hook to the proper address
contract CounterScript is Script {
    // provided in anvil, by default
    // https://github.com/Arachnid/deterministic-deployment-proxy
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    uint160 constant UNISWAP_FLAG_MASK = 0xff << 152;

    function setUp() public {}

    function run() public {
        vm.broadcast();
        PoolManager manager = new PoolManager(500000);

        // hook contracts must have specific flags encoded in the address
        uint160 targetFlags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_MODIFY_POSITION_FLAG
                | Hooks.AFTER_MODIFY_POSITION_FLAG
        );

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory hookBytecode = abi.encodePacked(type(Counter).creationCode, abi.encode(address(manager)));
        (address hook, uint256 salt) = mineSalt(targetFlags, hookBytecode);
        require(uint160(hook) & UNISWAP_FLAG_MASK == targetFlags, "CounterScript: could not find hook address");

        // Deploy the hook using the CREATE2 Deployer Proxy (provided by anvil)
        vm.broadcast();
        (bool success,) = address(CREATE2_DEPLOYER).call(abi.encodePacked(salt, hookBytecode));
        require(success, "CounterScript: could not deploy hook");

        // Additional helpers for interacting with the pool
        vm.startBroadcast();
        new PoolModifyPositionTest(IPoolManager(address(manager)));
        new PoolSwapTest(IPoolManager(address(manager)));
        new PoolDonateTest(IPoolManager(address(manager)));
        vm.stopBroadcast();
    }

    function mineSalt(uint160 targetFlags, bytes memory creationCode)
        internal
        pure
        returns (address hook, uint256 salt)
    {
        for (salt; salt < 1000;) {
            hook = _getAddress(salt, creationCode);
            uint160 prefix = uint160(hook) & UNISWAP_FLAG_MASK;
            if (prefix == targetFlags) {
                break;
            }

            unchecked {
                ++salt;
            }
        }
    }

    /// @notice Precompute a contract address that is deployed with the CREATE2Deployer
    function _getAddress(uint256 salt, bytes memory creationCode) internal pure returns (address) {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), CREATE2_DEPLOYER, salt, keccak256(creationCode)))))
        );
    }
}
