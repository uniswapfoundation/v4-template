// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

import {VCOPCollateralHook} from "../src/VcopCollateral/VCOPCollateralHook.sol";

/// @notice Script to mine and deploy the VCOPCollateralHook
contract DeployVCOPCollateralHook is Script {
    // Standard CREATE2 deployer address
    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
    
    // Hardcoded addresses as fallback
    address constant DEPLOYED_USDC_ADDRESS = 0x836C5578Dfa06EB3fCA056bdbB998433ddD12d6B;
    address constant DEPLOYED_VCOP_ADDRESS = 0x180e67aE4a941E9213425b962b06b8578B2fEf5C;
    address constant DEPLOYED_ORACLE_ADDRESS = 0x45C52AF0B64C053E0DC193369facF3c1a8718A3a;
    address constant DEPLOYED_COLLATERAL_MANAGER_ADDRESS = 0x962e3b4CA8587B59475b8204137Fa06cB7302d87;

    function run() public returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        // Get addresses using hardcoded fallback if environment variable is not available
        address poolManagerAddress;
        try vm.envAddress("POOL_MANAGER_ADDRESS") returns (address addr) {
            poolManagerAddress = addr;
        } catch {
            revert("POOL_MANAGER_ADDRESS not found in environment variables");
        }
        
        // Get VCOP address or use hardcoded one
        address vcopAddress;
        try vm.envAddress("VCOP_ADDRESS") returns (address addr) {
            if(addr != address(0)) {
                vcopAddress = addr;
                console2.log("VCOP address loaded from environment variables");
            } else {
                vcopAddress = DEPLOYED_VCOP_ADDRESS;
                console2.log("VCOP address using hardcoded value");
            }
        } catch {
            vcopAddress = DEPLOYED_VCOP_ADDRESS;
            console2.log("VCOP address using hardcoded value");
        }
        
        // Get Oracle address or use hardcoded one
        address oracleAddress;
        try vm.envAddress("ORACLE_ADDRESS") returns (address addr) {
            if(addr != address(0)) {
                oracleAddress = addr;
                console2.log("Oracle address loaded from environment variables");
            } else {
                oracleAddress = DEPLOYED_ORACLE_ADDRESS;
                console2.log("Oracle address using hardcoded value");
            }
        } catch {
            oracleAddress = DEPLOYED_ORACLE_ADDRESS;
            console2.log("Oracle address using hardcoded value");
        }
        
        // Get USDC address or use hardcoded one
        address usdcAddress;
        try vm.envAddress("USDC_ADDRESS") returns (address addr) {
            if(addr != address(0)) {
                usdcAddress = addr;
                console2.log("USDC address loaded from environment variables");
            } else {
                usdcAddress = DEPLOYED_USDC_ADDRESS;
                console2.log("USDC address using hardcoded value");
            }
        } catch {
            usdcAddress = DEPLOYED_USDC_ADDRESS;
            console2.log("USDC address using hardcoded value");
        }
        
        // Get Collateral Manager address or use hardcoded one
        address collateralManagerAddress;
        try vm.envAddress("COLLATERAL_MANAGER_ADDRESS") returns (address addr) {
            if(addr != address(0)) {
                collateralManagerAddress = addr;
                console2.log("CollateralManager address loaded from environment variables");
            } else {
                collateralManagerAddress = DEPLOYED_COLLATERAL_MANAGER_ADDRESS;
                console2.log("CollateralManager address using hardcoded value");
            }
        } catch {
            collateralManagerAddress = DEPLOYED_COLLATERAL_MANAGER_ADDRESS;
            console2.log("CollateralManager address using hardcoded value");
        }
        
        // Use deployer as treasury by default
        address treasuryAddress = deployerAddress;
        
        // Flags for the hook (beforeSwap, afterSwap, afterAddLiquidity)
        uint160 hookFlags = uint160(
            Hooks.BEFORE_SWAP_FLAG | 
            Hooks.AFTER_SWAP_FLAG | 
            Hooks.AFTER_ADD_LIQUIDITY_FLAG
        );
        
        // Create Currency for VCOP and USDC
        Currency vcopCurrency = Currency.wrap(vcopAddress);
        Currency usdcCurrency = Currency.wrap(usdcAddress);
        
        console2.log("Mining hook address...");
        
        // Log addresses being used
        console2.log("Using the following addresses:");
        console2.log("USDC:", usdcAddress);
        console2.log("VCOP:", vcopAddress);
        console2.log("Oracle:", oracleAddress);
        console2.log("CollateralManager:", collateralManagerAddress);
        
        // Encode constructor arguments
        bytes memory constructorArgs = abi.encode(
            IPoolManager(poolManagerAddress),
            collateralManagerAddress,
            oracleAddress,
            vcopCurrency,
            usdcCurrency,
            treasuryAddress,
            deployerAddress
        );
        
        // Use HookMiner to find a valid address
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            hookFlags,
            type(VCOPCollateralHook).creationCode,
            constructorArgs
        );
        
        console2.log("Address found:", hookAddress);
        console2.log("With salt:", vm.toString(salt));
        
        // Broadcast transaction to deploy the hook
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the hook using CREATE2 with the mined salt
        VCOPCollateralHook hook = new VCOPCollateralHook{salt: salt}(
            IPoolManager(poolManagerAddress),
            collateralManagerAddress,
            oracleAddress,
            vcopCurrency,
            usdcCurrency,
            treasuryAddress,
            deployerAddress
        );
        
        // Verify that it was deployed at the expected address
        require(address(hook) == hookAddress, "Error in hook address");
        
        console2.log("VCOPCollateralHook deployed at:", address(hook));
        console2.log("Owner set as the deployer:", deployerAddress);
        
        vm.stopBroadcast();
        
        // Return the hook address so it can be used by the main script
        return address(hook);
    }
} 