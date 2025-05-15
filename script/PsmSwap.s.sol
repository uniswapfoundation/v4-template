// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {VCOPCollateralHook} from "../src/VcopCollateral/VCOPCollateralHook.sol";
import {VCOPCollateralized} from "../src/VcopCollateral/VCOPCollateralized.sol";

/**
 * @title PsmSwap
 * @notice Script to execute PSM swaps (VCOP to USDC or USDC to VCOP)
 * @dev Run with: forge script script/PsmSwap.s.sol:PsmSwapScript --rpc-url https://sepolia.base.org --broadcast
 */
contract PsmSwapScript is Script {
    // Contract addresses
    address public constant USDC_ADDRESS = 0x8FB0502d06253915db48b7F5D0bf446B17265C73;
    address public constant VCOP_ADDRESS = 0x97CBc4fB89a85681b5f2da1c5569b7938ff8bFa3;
    address public constant VCOP_HOOK_ADDRESS = 0x07CFb798c049E71F8D140AEE17c1DE2e647Dc4c0;
    
    // Swap configuration
    uint256 public swapAmount = 100 * 1e6; // 100 tokens (assuming 6 decimals)
    bool public swapVCOPForCollateral = true; // Set to true for VCOP->USDC, false for USDC->VCOP
    
    function setUp() public {
        // Load environment variables
        // Private key is loaded automatically with --broadcast flag
    }

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);
        
        if (swapVCOPForCollateral) {
            swapVcopToUsdc(swapAmount);
        } else {
            swapUsdcToVcop(swapAmount);
        }
        
        vm.stopBroadcast();
    }
    
    /**
     * @dev Swap VCOP for USDC using PSM
     * @param amount Amount of VCOP to swap (in VCOP units with 6 decimals)
     */
    function swapVcopToUsdc(uint256 amount) internal {
        VCOPCollateralHook hook = VCOPCollateralHook(VCOP_HOOK_ADDRESS);
        IERC20 vcop = IERC20(VCOP_ADDRESS);
        
        // Check balance
        uint256 balance = vcop.balanceOf(msg.sender);
        require(balance >= amount, "Insufficient VCOP balance");
        
        console.log("VCOP Balance Before Swap:", balance);
        
        // Approve VCOP for hook to transfer
        vcop.approve(VCOP_HOOK_ADDRESS, amount);
        console.log("Approved VCOP for PSM swap:", amount);
        
        // Execute swap
        hook.psmSwapVCOPForCollateral(amount);
        console.log("Swapped VCOP for USDC:", amount);
        
        // Log updated balances
        uint256 newVcopBalance = vcop.balanceOf(msg.sender);
        uint256 newUsdcBalance = IERC20(USDC_ADDRESS).balanceOf(msg.sender);
        console.log("VCOP Balance After Swap:", newVcopBalance);
        console.log("USDC Balance After Swap:", newUsdcBalance);
    }
    
    /**
     * @dev Swap USDC for VCOP using PSM
     * @param amount Amount of USDC to swap (in USDC units with 6 decimals)
     */
    function swapUsdcToVcop(uint256 amount) internal {
        VCOPCollateralHook hook = VCOPCollateralHook(VCOP_HOOK_ADDRESS);
        IERC20 usdc = IERC20(USDC_ADDRESS);
        
        // Check balance
        uint256 balance = usdc.balanceOf(msg.sender);
        require(balance >= amount, "Insufficient USDC balance");
        
        console.log("USDC Balance Before Swap:", balance);
        
        // Approve USDC for hook to transfer
        usdc.approve(VCOP_HOOK_ADDRESS, amount);
        console.log("Approved USDC for PSM swap:", amount);
        
        // Execute swap
        hook.psmSwapCollateralForVCOP(amount);
        console.log("Swapped USDC for VCOP:", amount);
        
        // Log updated balances
        uint256 newUsdcBalance = usdc.balanceOf(msg.sender);
        uint256 newVcopBalance = IERC20(VCOP_ADDRESS).balanceOf(msg.sender);
        console.log("USDC Balance After Swap:", newUsdcBalance);
        console.log("VCOP Balance After Swap:", newVcopBalance);
    }
} 