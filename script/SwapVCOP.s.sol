// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract SwapVCOPScript is Script {
    // slippage tolerance to allow for unlimited price impact
    uint160 public constant MIN_PRICE_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
    uint160 public constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

    // VCOP Token address
    address public constant VCOP_ADDRESS = 0xd16Ee99c7EA2B30c13c3dC298EADEE00B870BBCC;
    // USDC Token address
    address public constant USDC_ADDRESS = 0xE7a4113a8a497DD72D29F35E188eEd7403e8B2E8;
    // VCOP Rebase Hook
    address public constant HOOK_ADDRESS = 0x866bf94370e8A7C9cDeAFb592C2ac62903e30040;
    
    // Base Sepolia deployed contracts
    address public constant POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
    address public constant UNIVERSAL_ROUTER = 0x492E6456D9528771018DeB9E87ef7750EF184104;
    address public constant POSITION_MANAGER = 0x4B2C77d209D3405F41a037Ec6c77F7F5b8e2ca80;
    address public constant POOL_SWAP_TEST = 0x8B5bcC363ddE2614281aD875bad385E0A785D3B9;
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // Pool configuration
    uint24 public constant LP_FEE = 3000; // 0.30%
    int24 public constant TICK_SPACING = 60;

    // Amount of VCOP to swap (49,000 VCOP with 6 decimals)
    uint256 public constant SWAP_AMOUNT = 49_000 * 10**6;

    function run() external {
        // Create pool key
        PoolKey memory pool = PoolKey({
            currency0: Currency.wrap(VCOP_ADDRESS),
            currency1: Currency.wrap(USDC_ADDRESS),
            fee: LP_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(HOOK_ADDRESS)
        });

        IERC20 vcopToken = IERC20(VCOP_ADDRESS);
        IERC20 usdcToken = IERC20(USDC_ADDRESS);

        // Approve tokens to the swap router
        vm.startBroadcast();
        
        // Approve VCOP tokens for swapping
        vcopToken.approve(POOL_SWAP_TEST, type(uint256).max);

        // Set swap parameters - we want to swap VCOP (token0) for USDC (token1)
        bool zeroForOne = true;
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: int256(SWAP_AMOUNT), // 49,000 VCOP with 6 decimals
            sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT // unlimited impact
        });

        // Configure test settings - receive native ERC20s
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        // Execute the swap
        bytes memory hookData = new bytes(0);
        PoolSwapTest(POOL_SWAP_TEST).swap(pool, params, testSettings, hookData);
        
        vm.stopBroadcast();

        // Log balances after swap (for informational purposes)
        uint256 vcopBalance = vcopToken.balanceOf(msg.sender);
        uint256 usdcBalance = usdcToken.balanceOf(msg.sender);
        console.log("VCOP Balance after swap:", vcopBalance);
        console.log("USDC Balance after swap:", usdcBalance);
    }
} 