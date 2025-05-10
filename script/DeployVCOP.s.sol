// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

import {VCOPRebased} from "../src/VCOPRebased.sol";
import {VCOPOracle} from "../src/VCOPOracle.sol";
import {VCOPRebaseHook} from "../src/VCOPRebaseHook.sol";

contract DeployVCOP is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        address stablecoinAddress = vm.envAddress("STABLECOIN_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Despliegue inicial de VCOP con un suministro de 1,000,000 tokens
        VCOPRebased vcop = new VCOPRebased(1_000_000 * 1e18);
        
        // Despliegue del oráculo con precio inicial de 1 USD
        VCOPOracle oracle = new VCOPOracle(1e18);
        
        // Despliegue del hook de rebase
        VCOPRebaseHook hook = new VCOPRebaseHook(
            IPoolManager(poolManagerAddress),
            address(vcop),
            address(oracle),
            Currency.wrap(address(vcop)),
            Currency.wrap(stablecoinAddress)
        );
        
        // Autorizar al hook para ejecutar rebases
        vcop.setRebaser(address(hook), true);
        
        console.log("VCOP Token desplegado en:", address(vcop));
        console.log("VCOP Oracle desplegado en:", address(oracle));
        console.log("VCOP Rebase Hook desplegado en:", address(hook));
        
        vm.stopBroadcast();
    }
}

/**
 * Script para desplegar una versión de desarrollo con tokens mock
 */
contract DeployVCOPDev is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Desplegar stablecoin mock (USDC)
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        usdc.mint(msg.sender, 1_000_000 * 1e6);
        
        // Despliegue inicial de VCOP con un suministro de 1,000,000 tokens
        VCOPRebased vcop = new VCOPRebased(1_000_000 * 1e18);
        
        // Despliegue del oráculo con precio inicial de 1 USD
        VCOPOracle oracle = new VCOPOracle(1e18);
        
        // Despliegue del hook de rebase
        VCOPRebaseHook hook = new VCOPRebaseHook(
            IPoolManager(poolManagerAddress),
            address(vcop),
            address(oracle),
            Currency.wrap(address(vcop)),
            Currency.wrap(address(usdc))
        );
        
        // Autorizar al hook para ejecutar rebases
        vcop.setRebaser(address(hook), true);
        
        console.log("Mock USDC desplegado en:", address(usdc));
        console.log("VCOP Token desplegado en:", address(vcop));
        console.log("VCOP Oracle desplegado en:", address(oracle));
        console.log("VCOP Rebase Hook desplegado en:", address(hook));
        
        vm.stopBroadcast();
    }
} 