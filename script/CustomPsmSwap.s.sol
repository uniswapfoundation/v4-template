// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {VCOPCollateralHook} from "../src/VcopCollateral/VCOPCollateralHook.sol";
import {VCOPCollateralized} from "../src/VcopCollateral/VCOPCollateralized.sol";
import {VCOPOracle} from "../src/VcopCollateral/VCOPOracle.sol";

/**
 * @title CustomPsmSwap
 * @notice Script to execute PSM swaps with custom parameters
 * @dev Run with: 
 *   For VCOP to USDC swap: forge script script/CustomPsmSwap.s.sol:CustomPsmSwapScript --sig 'swapVcopToUsdc(uint256)' 100000000 --rpc-url https://sepolia.base.org --broadcast
 *   For USDC to VCOP swap: forge script script/CustomPsmSwap.s.sol:CustomPsmSwapScript --sig 'swapUsdcToVcop(uint256)' 100000000 --rpc-url https://sepolia.base.org --broadcast
 */
contract CustomPsmSwapScript is Script {
    // Contract addresses (actualizadas al nuevo despliegue)
    address public constant USDC_ADDRESS = 0x5405e3a584014c8659BA10591c1b7D55cB1cFc0d;
    address public constant VCOP_ADDRESS = 0x3D384BeB1Ba0197e6a87668E1D68267164c8B776;
    address public constant VCOP_HOOK_ADDRESS = 0xb1D909689f88Bd34340f477A0Bad3956113944C0;
    address public constant VCOP_ORACLE_ADDRESS = 0x046fFDe3161CD0a8DCBF7e1c433f5f510703d56d;

    // Setup function - update logger config
    function setUp() public {}

    // Get account address from private key
    function getAccount() internal returns (address) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        return vm.addr(privateKey);
    }
    
    /**
     * @dev Swap VCOP for USDC using PSM (expose as external for command line usage)
     * @param amount Amount of VCOP to swap (in VCOP units with 6 decimals)
     */
    function swapVcopToUsdc(uint256 amount) external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);
        
        address account = vm.addr(privateKey);
        VCOPCollateralHook hook = VCOPCollateralHook(VCOP_HOOK_ADDRESS);
        IERC20 vcop = IERC20(VCOP_ADDRESS);
        IERC20 usdc = IERC20(USDC_ADDRESS);
        
        // Log initial status
        console.log("=== VCOP to USDC Swap ===");
        console.log("Account:", account);
        
        // Check balance
        uint256 vcopBalance = vcop.balanceOf(account);
        uint256 usdcBalanceBefore = usdc.balanceOf(account);
        console.log("Initial VCOP balance:", vcopBalance);
        console.log("Initial USDC balance:", usdcBalanceBefore);
        
        // Check calculation
        uint256 expectedUsdc = hook.calculateCollateralForVCOPView(amount);
        console.log("Expected USDC output (before fees):", expectedUsdc);
        
        require(vcopBalance >= amount, "Insufficient VCOP balance");
        
        // Approve VCOP for hook to transfer
        console.log("Approving VCOP for hook...");
        vcop.approve(VCOP_HOOK_ADDRESS, amount);
        
        // Execute swap
        console.log("Executing swap...");
        hook.psmSwapVCOPForCollateral(amount);
        
        // Log updated balances
        uint256 newVcopBalance = vcop.balanceOf(account);
        uint256 newUsdcBalance = usdc.balanceOf(account);
        
        console.log("=== Swap Complete ===");
        console.log("New VCOP balance:", newVcopBalance);
        console.log("New USDC balance:", newUsdcBalance);
        console.log("VCOP spent:", vcopBalance - newVcopBalance);
        console.log("USDC received:", newUsdcBalance - usdcBalanceBefore);
        
        vm.stopBroadcast();
    }
    
    /**
     * @dev Swap USDC for VCOP using PSM (expose as external for command line usage)
     * @param amount Amount of USDC to swap (in USDC units with 6 decimals)
     */
    function swapUsdcToVcop(uint256 amount) external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);
        
        address account = vm.addr(privateKey);
        VCOPCollateralHook hook = VCOPCollateralHook(VCOP_HOOK_ADDRESS);
        IERC20 usdc = IERC20(USDC_ADDRESS);
        IERC20 vcop = IERC20(VCOP_ADDRESS);
        
        // Log initial status
        console.log("=== USDC to VCOP Swap ===");
        console.log("Account:", account);
        
        // Check balance
        uint256 usdcBalance = usdc.balanceOf(account);
        uint256 vcopBalanceBefore = vcop.balanceOf(account);
        console.log("Initial USDC balance:", usdcBalance);
        console.log("Initial VCOP balance:", vcopBalanceBefore);
        
        // Check calculation
        uint256 expectedVcop = hook.calculateVCOPForCollateralView(amount);
        console.log("Expected VCOP output (before fees):", expectedVcop);
        
        require(usdcBalance >= amount, "Insufficient USDC balance");
        
        // Approve USDC for hook to transfer
        console.log("Approving USDC for hook...");
        usdc.approve(VCOP_HOOK_ADDRESS, amount);
        
        // Execute swap
        console.log("Executing swap...");
        hook.psmSwapCollateralForVCOP(amount);
        
        // Log updated balances
        uint256 newUsdcBalance = usdc.balanceOf(account);
        uint256 newVcopBalance = vcop.balanceOf(account);
        
        console.log("=== Swap Complete ===");
        console.log("New USDC balance:", newUsdcBalance);
        console.log("New VCOP balance:", newVcopBalance);
        console.log("USDC spent:", usdcBalance - newUsdcBalance);
        console.log("VCOP received:", newVcopBalance - vcopBalanceBefore);
        
        vm.stopBroadcast();
    }
    
    /**
     * @dev View current PSM prices and do a dry run calculation
     */
    function checkPrices() external {
        // Use view call for checking - no private key needed
        VCOPCollateralHook hook = VCOPCollateralHook(VCOP_HOOK_ADDRESS);
        VCOPOracle oracle = VCOPOracle(VCOP_ORACLE_ADDRESS);
        
        uint256 testAmount = 100 * 1e6; // 100 tokens
        
        // Calculate both directions
        uint256 usdcForVcop = hook.calculateCollateralForVCOPView(testAmount);
        uint256 vcopForUsdc = hook.calculateVCOPForCollateralView(testAmount);
        
        // Current rates from oracle
        uint256 vcopToCopRate = oracle.getVcopToCopRateView();
        uint256 usdToCopRate = oracle.getUsdToCopRateView();
        
        console.log("=== PSM Price Check ===");
        console.log("VCOP/COP rate:", vcopToCopRate);
        console.log("USD/COP rate:", usdToCopRate);
        console.log("100 VCOP = %s USDC", usdcForVcop);
        console.log("100 USDC = %s VCOP", vcopForUsdc);
        
        // Check PSM fees
        uint256 psmFee = hook.psmFee();
        console.log("PSM fee: %s basis points", psmFee);
    }
} 