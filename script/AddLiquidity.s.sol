// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {CurrencyLibrary} from "v4-core/src/types/Currency.sol";

/**
 * @title AddLiquidity
 * @notice Simple script to add liquidity to the VCOP/USDC pool
 */
contract AddLiquidity is Script {
    using CurrencyLibrary for Currency;

    // Constantes de Uniswap V4 - Direcciones oficiales de Base Sepolia
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(address(0x000000000022D473030F116dDEE9F6B43aC78BA3));
    
    // Configuracion para la posicion de liquidez inicial
    uint256 vcopLiquidity = 50 * 1e18; // 50 VCOP
    uint256 stablecoinLiquidity = 50 * 1e6; // 50 USDC (6 decimales)
    int24 tickLower = -600;
    int24 tickUpper = 600;
    uint160 startingPrice = 79228162514264337593543950336; // sqrt(1) * 2^96

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        address positionManagerAddress = vm.envAddress("POSITION_MANAGER_ADDRESS");
        address vcopAddress = vm.envAddress("VCOP_ADDRESS");
        address hookAddress = vm.envAddress("HOOK_ADDRESS");
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // References
        PositionManager positionManager = PositionManager(payable(positionManagerAddress));
        IERC20 vcop = IERC20(vcopAddress);
        IERC20 usdc = IERC20(usdcAddress);
        
        // Create currencies
        Currency vcopCurrency = Currency.wrap(vcopAddress);
        Currency usdcCurrency = Currency.wrap(usdcAddress);
        
        // Determine token order
        Currency currency0;
        Currency currency1;
        bool vcopIsToken0;
        
        if (vcopAddress < usdcAddress) {
            currency0 = vcopCurrency;
            currency1 = usdcCurrency;
            vcopIsToken0 = true;
            console.log("VCOP is token0");
        } else {
            currency0 = usdcCurrency;
            currency1 = vcopCurrency;
            vcopIsToken0 = false;
            console.log("USDC is token0");
        }
        
        // Check balances
        uint256 usdcBalance = usdc.balanceOf(msg.sender);
        uint256 vcopBalance = vcop.balanceOf(msg.sender);
        
        console.log("USDC Balance:", usdcBalance);
        console.log("VCOP Balance:", vcopBalance);
        console.log("USDC Needed:", stablecoinLiquidity);
        console.log("VCOP Needed:", vcopLiquidity);
        
        require(usdcBalance >= stablecoinLiquidity, "Insufficient USDC");
        require(vcopBalance >= vcopLiquidity, "Insufficient VCOP");
        
        // Create pool key
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000, // 0.3%
            tickSpacing: 60,
            hooks: IHooks(hookAddress)
        });
        
        // Calculate liquidity
        uint256 amount0Max = vcopIsToken0 ? vcopLiquidity : stablecoinLiquidity;
        uint256 amount1Max = vcopIsToken0 ? stablecoinLiquidity : vcopLiquidity;
        
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0Max,
            amount1Max
        );
        
        // Approve tokens
        _approveTokens(vcopAddress, usdcAddress, address(positionManager));
        
        // Add liquidity
        (bytes memory actions, bytes[] memory mintParams) = _prepareMintParams(
            key, 
            tickLower, 
            tickUpper, 
            liquidity, 
            amount0Max, 
            amount1Max
        );
        
        positionManager.modifyLiquidities(
            abi.encode(actions, mintParams),
            block.timestamp + 60
        );
        
        console.log("Liquidity added successfully");
        
        vm.stopBroadcast();
    }
    
    function _prepareMintParams(
        PoolKey memory key,
        int24 _tickLower,
        int24 _tickUpper,
        uint128 liquidity,
        uint256 amount0Max,
        uint256 amount1Max
    ) internal view returns (bytes memory, bytes[] memory) {
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));
        
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(key, _tickLower, _tickUpper, liquidity, amount0Max, amount1Max, msg.sender, new bytes(0));
        params[1] = abi.encode(key.currency0, key.currency1);
        
        return (actions, params);
    }
    
    function _approveTokens(address vcopAddress, address usdcAddress, address positionManagerAddress) internal {
        // Approve VCOP
        IERC20(vcopAddress).approve(address(PERMIT2), type(uint256).max);
        PERMIT2.approve(vcopAddress, positionManagerAddress, type(uint160).max, type(uint48).max);
        
        // Approve USDC
        IERC20(usdcAddress).approve(address(PERMIT2), type(uint256).max);
        PERMIT2.approve(usdcAddress, positionManagerAddress, type(uint160).max, type(uint48).max);
    }
} 