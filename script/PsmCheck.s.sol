// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {VCOPCollateralHook} from "../src/VcopCollateral/VCOPCollateralHook.sol";
import {VCOPCollateralManager} from "../src/VcopCollateral/VCOPCollateralManager.sol";

/**
 * @title PsmCheck
 * @notice Script to check status of PSM reserves and conditions
 * @dev Run with: forge script script/PsmCheck.s.sol:PsmCheckScript --rpc-url https://sepolia.base.org
 */
contract PsmCheckScript is Script {
    // Contract addresses
    address public constant USDC_ADDRESS = 0x1D954BcfB060a3dc5A49536243545334dD536493;
    address public constant VCOP_ADDRESS = 0xbbF67a9C2a6E33B405ff30C948275c2154B36E3A;
    address public constant VCOP_HOOK_ADDRESS = 0xe0457171D72461135346bcEAc4BF1F381c61C4C0;
    address public constant COLLATERAL_MANAGER_ADDRESS = 0x2D644FC74e5fe6598b0843f149b02bFEf99Ef383;
    address public constant PRICE_CALCULATOR_ADDRESS = 0xc43DedA1ECD3Ba5e3b1C71d573A069cDCF5FaB47;

    function setUp() public {
        // Nothing to set up
    }
    
    function run() public {
        // Load private key but don't broadcast transactions
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(privateKey);
        
        // Check user balances
        checkBalances(user);
        
        // Check PSM status
        checkPsmStatus();
        
        // Check price data
        checkPrices();
    }
    
    function checkBalances(address user) internal {
        IERC20 vcop = IERC20(VCOP_ADDRESS);
        IERC20 usdc = IERC20(USDC_ADDRESS);
        
        uint256 vcopBalance = vcop.balanceOf(user);
        uint256 usdcBalance = usdc.balanceOf(user);
        
        console.log("======= User Balances =======");
        console.log("User address:", user);
        console.log("VCOP balance:", vcopBalance);
        console.log("USDC balance:", usdcBalance);
        console.log("============================");
    }
    
    function checkPsmStatus() internal {
        VCOPCollateralHook hook = VCOPCollateralHook(VCOP_HOOK_ADDRESS);
        VCOPCollateralManager manager = VCOPCollateralManager(COLLATERAL_MANAGER_ADDRESS);
        
        // Get PSM stats
        (
            uint256 vcopReserve, 
            uint256 collateralReserve, 
            uint256 lastOperationTimestamp, 
            uint256 totalSwapsCount
        ) = hook.getPSMStats();
        
        // Check if PSM is paused
        bool isPaused = hook.psmPaused();
        
        console.log("======= PSM Status =======");
        console.log("PSM paused:", isPaused);
        console.log("VCOP reserve:", vcopReserve);
        console.log("USDC reserve:", collateralReserve);
        console.log("Last operation timestamp:", lastOperationTimestamp);
        console.log("Total swaps:", totalSwapsCount);
        
        // Get PSM parameters
        uint256 psmFee = hook.psmFee();
        uint256 psmMaxSwapAmount = hook.psmMaxSwapAmount();
        
        console.log("PSM fee:", psmFee);
        console.log("PSM max swap amount:", psmMaxSwapAmount);
        
        // Get peg bounds
        uint256 pegUpperBound = hook.pegUpperBound();
        uint256 pegLowerBound = hook.pegLowerBound();
        
        console.log("Peg upper bound:", pegUpperBound);
        console.log("Peg lower bound:", pegLowerBound);
        console.log("==========================");
    }
    
    function checkPrices() internal {
        VCOPCollateralHook hook = VCOPCollateralHook(VCOP_HOOK_ADDRESS);
        
        // Calculate conversion rates for test amounts
        uint256 vcopAmount = 1000 * 1e6; // 1,000 VCOP
        uint256 usdcAmount = 1000 * 1e6; // 1,000 USDC
        
        uint256 collateralForVcop = hook.calculateCollateralForVCOPView(vcopAmount);
        uint256 vcopForCollateral = hook.calculateVCOPForCollateralView(usdcAmount);
        
        console.log("======= Price Calculations =======");
        console.log("1,000 VCOP = ", collateralForVcop, " USDC");
        console.log("1,000 USDC = ", vcopForCollateral, " VCOP");
        console.log("================================");
    }
} 