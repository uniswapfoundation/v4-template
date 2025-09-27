// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {PerpsHook} from "../src/PerpsHook.sol";
import {PositionManager} from "../src/PositionManagerV2.sol";
import {PositionFactory} from "../src/PositionFactory.sol";
import {PositionNFT} from "../src/PositionNFT.sol";
import {MarketManager} from "../src/MarketManager.sol";
import {MarginAccount} from "../src/MarginAccount.sol";
import {FundingOracle} from "../src/FundingOracle.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployPerpsHookScript is Script {
    
    function run() external {
        console.log("Deploying PerpsHook with deployer:", msg.sender);
        console.log("Deployer balance:", msg.sender.balance);
        
        // Hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | 
            Hooks.BEFORE_SWAP_FLAG | 
            Hooks.AFTER_SWAP_FLAG |
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
            Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );

        deployHook(flags);
    }
    
    function deployHook(uint160 flags) internal {
        // Known addresses from deployment
        address POOL_MANAGER_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // PoolManager
        address POSITION_MANAGER_ADDRESS = 0x4A679253410272dd5232B3Ff7cF5dbB88f295319; // Deployed PositionManager
        address POSITION_FACTORY_ADDRESS = 0x322813Fd9A801c5507c9de605d63CEA4f2CE6c44; // Deployed PositionFactory
        address MARGIN_ACCOUNT_ADDRESS = 0x8A791620dd6260079BF849Dc5567aDC3F2FdC318; // Deployed MarginAccount
        address payable FUNDING_ORACLE_ADDRESS = payable(0x5FbDB2315678afecb367f032d93F642f64180aa3); // Deployed FundingOracle
        address USDC_ADDRESS = 0x7c5A2E8320FAE0e0B2b3C1F0A5A5BC9b2d3e4e5f; // MockUSDC
        
        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(
            IPoolManager(POOL_MANAGER_ADDRESS), 
            PositionManager(POSITION_MANAGER_ADDRESS), 
            PositionFactory(POSITION_FACTORY_ADDRESS), 
            MarginAccount(MARGIN_ACCOUNT_ADDRESS), 
            FundingOracle(FUNDING_ORACLE_ADDRESS), 
            IERC20(USDC_ADDRESS)
        );
        
        (address hookAddress, bytes32 salt) =
            HookMiner.find(0x4e59b44847b379578588920cA78FbF26c0B4956C, flags, type(PerpsHook).creationCode, constructorArgs);

        console.log("Target hook address:", hookAddress);
        console.log("Salt:", vm.toString(salt));

        // Deploy the hook using CREATE2
        vm.startBroadcast();
        PerpsHook perpsHook = new PerpsHook{salt: salt}(
            IPoolManager(POOL_MANAGER_ADDRESS), 
            PositionManager(POSITION_MANAGER_ADDRESS), 
            PositionFactory(POSITION_FACTORY_ADDRESS), 
            MarginAccount(MARGIN_ACCOUNT_ADDRESS), 
            FundingOracle(FUNDING_ORACLE_ADDRESS), 
            IERC20(USDC_ADDRESS)
        );
        vm.stopBroadcast();

        require(address(perpsHook) == hookAddress, "DeployPerpsHookScript: Hook Address Mismatch");
        
        console.log("PerpsHook deployed to:", address(perpsHook));
        console.log("Using PositionManager at:", POSITION_MANAGER_ADDRESS);
        console.log("Using PositionFactory at:", POSITION_FACTORY_ADDRESS);
        console.log("Using MarginAccount at:", MARGIN_ACCOUNT_ADDRESS);
        console.log("Using FundingOracle at:", FUNDING_ORACLE_ADDRESS);
        console.log("Using USDC at:", USDC_ADDRESS);
        console.log("Hook permissions verified!");
        
        // Verify hook has correct flags
        console.log("Hook flags verified for integrated trading system");
    }
}
