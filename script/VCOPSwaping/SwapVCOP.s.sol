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
import "./VCOPSwapConfig.sol";

contract SwapVCOPScript is Script {
    // slippage tolerance
    uint160 public constant MIN_PRICE_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
    uint160 public constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

    // VCOP Token address - ACTUALIZADO
    address public constant VCOP_ADDRESS = 0x70370F8507f0c40D5Ed3222F669B0727FFF8C12c;
    // USDC Token address - ACTUALIZADO
    address public constant USDC_ADDRESS = 0xAE919425E485C6101E391091350E3f0304749574;
    // VCOP Rebase Hook - ACTUALIZADO
    address public constant HOOK_ADDRESS = 0x1E70FbbF7A9ADcD550BaeE80E58B244EcdFF0040;
    
    // Base Sepolia deployed contracts
    address public constant POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
    address public constant UNIVERSAL_ROUTER = 0x492E6456D9528771018DeB9E87ef7750EF184104;
    address public constant POSITION_MANAGER = 0x4B2C77d209D3405F41a037Ec6c77F7F5b8e2ca80;
    address public constant POOL_SWAP_TEST = 0x8B5bcC363ddE2614281aD875bad385E0A785D3B9;
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // Pool configuration
    uint24 public constant LP_FEE = 3000; // 0.30%
    int24 public constant TICK_SPACING = 60;

    function run() external {
        // Cargar configuración desde VCOPSwapConfig
        VCOPSwapConfig config = new VCOPSwapConfig();
        bool comprarVCOP = config.COMPRAR_VCOP();
        uint256 cantidad = config.CANTIDAD();
        uint16 slippageMax = config.SLIPPAGE_MAX();
        
        console.log("Modo:", comprarVCOP ? "Comprar VCOP con USDC" : "Vender VCOP por USDC");
        console.log("Cantidad:", cantidad / 10**6, "tokens");
        
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

        vm.startBroadcast();
        
        // Definir dirección del swap:
        // - Si compramos VCOP: USDC (token1) a VCOP (token0) -> zeroForOne = false
        // - Si vendemos VCOP: VCOP (token0) a USDC (token1) -> zeroForOne = true
        bool zeroForOne = !comprarVCOP;
        
        // Aprobar tokens según dirección
        if (comprarVCOP) {
            usdcToken.approve(POOL_SWAP_TEST, type(uint256).max);
        } else {
            vcopToken.approve(POOL_SWAP_TEST, type(uint256).max);
        }
        
        // amountSpecified negativo para entrada exacta
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(cantidad),
            sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
        });

        // Configure test settings
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        // Execute the swap
        bytes memory hookData = new bytes(0);
        PoolSwapTest(POOL_SWAP_TEST).swap(pool, params, testSettings, hookData);
        
        vm.stopBroadcast();

        // Log balances after swap
        uint256 vcopBalance = vcopToken.balanceOf(msg.sender);
        uint256 usdcBalance = usdcToken.balanceOf(msg.sender);
        console.log("VCOP Balance:", vcopBalance / 10**6);
        console.log("USDC Balance:", usdcBalance / 10**6);
    }
} 