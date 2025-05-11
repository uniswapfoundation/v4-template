// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Script simplificado para desplegar el sistema VCOP en Base Sepolia
// Ejecutar: forge script script/SimpleDeploy.sol:SimpleDeploy --via-ir --broadcast --fork-url https://sepolia.base.org

import {Script} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

import {VCOPRebased} from "../src/VCOPRebased.sol";
import {VCOPOracle} from "../src/VCOPOracle.sol";
import {DeployVCOPRebaseHook} from "./DeployVCOPRebaseHook.s.sol";
import {DeployMockUSDC} from "./DeployMockUSDC.s.sol";

contract SimpleDeploy is Script {
    using CurrencyLibrary for Currency;

    // Constantes de Uniswap V4 - Direcciones oficiales de Base Sepolia
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(address(0x000000000022D473030F116dDEE9F6B43aC78BA3));
    
    // Parametros configurables para el pool
    uint24 lpFee = 3000; // 0.30%
    int24 tickSpacing = 60;
    
    // Tasa inicial USD/COP (4200 COP = 1 USD)
    uint256 initialUsdToCopRate = 4200e6; // Con 6 decimales
    
    // Para una relacion 1:4200, usamos un precio inicial adecuado
    uint160 startingPrice;
    
    // Configuración para la posición de liquidez inicial
    uint256 stablecoinLiquidity = 100_000 * 1e6; // 100,000 USDC con 6 decimales
    uint256 vcopLiquidity = 420_000_000 * 1e6; // 420M VCOP (ratio 4200:1)
    
    // Ticks para el rango de liquidez
    int24 tickLower;
    int24 tickUpper;
    
    function run() public {
        // API Key dummy para Etherscan
        vm.setEnv("ETHERSCAN_API_KEY", "ABCDEFGHIJKLMNOPQRSTUVWXYZ123456");
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        address positionManagerAddress = vm.envAddress("POSITION_MANAGER_ADDRESS");
        
        // === PASO 1: Desplegar USDC simulado ===
        DeployMockUSDC usdcDeployer = new DeployMockUSDC();
        address usdcAddress = usdcDeployer.run();
        
        // Verificar el despliegue
        IERC20 usdc = IERC20(usdcAddress);
        uint256 usdcBalance = usdc.balanceOf(deployerAddress);
        
        // Comprobar si hay suficiente USDC
        require(usdcBalance >= stablecoinLiquidity, "Insuficiente USDC para agregar liquidez.");
        
        // Referencias a contratos externos de Uniswap
        IPoolManager poolManager = IPoolManager(poolManagerAddress);
        PositionManager positionManager = PositionManager(payable(positionManagerAddress));
        
        // === PASO 2: Desplegar VCOP y Oracle ===
        vm.startBroadcast(deployerPrivateKey);
        
        // Despliegue inicial de VCOP con 1,000,000,000 tokens (1000M)
        VCOPRebased vcop = new VCOPRebased(1_000_000_000 * 1e6);
        
        // Despliegue del oraculo con tasa inicial de 4200 COP = 1 USD
        VCOPOracle oracle = new VCOPOracle(initialUsdToCopRate);
        
        vm.stopBroadcast();
        
        // Guardar direcciones para el siguiente script
        vm.setEnv("VCOP_ADDRESS", vm.toString(address(vcop)));
        vm.setEnv("ORACLE_ADDRESS", vm.toString(address(oracle)));
        vm.setEnv("USDC_ADDRESS", vm.toString(usdcAddress));
        
        // === PASO 3: Desplegar Hook con HookMiner ===
        DeployVCOPRebaseHook hookDeployer = new DeployVCOPRebaseHook();
        hookDeployer.run();
        
        // Obtener la direccion del hook desplegado
        address hookAddress = vm.envOr("HOOK_ADDRESS", address(0));
        require(hookAddress != address(0), "Hook address not set");
        
        // === PASO 4: Crear Pool y añadir liquidez ===
        vm.startBroadcast(deployerPrivateKey);
        
        // Crear Currency para VCOP y USDC
        Currency vcopCurrency = Currency.wrap(address(vcop));
        Currency usdcCurrency = Currency.wrap(usdcAddress);
        
        // Asegurar que las monedas esten en orden correcto (menor direccion primero)
        Currency currency0;
        Currency currency1;
        bool vcopIsToken0;
        
        if (address(vcop) < usdcAddress) {
            currency0 = vcopCurrency;
            currency1 = usdcCurrency;
            vcopIsToken0 = true;
            
            // Si VCOP es token0, entonces para una relacion de 4200 VCOP = 1 USDC
            int24 targetTick = -83000;
            startingPrice = TickMath.getSqrtPriceAtTick(targetTick);
            
            tickLower = targetTick - 6000;
            tickUpper = targetTick + 6000;
            
        } else {
            currency0 = usdcCurrency;
            currency1 = vcopCurrency;
            vcopIsToken0 = false;
            
            // Si USDC es token0, precio debe ser alto (4200)
            int24 targetTick = 83000;
            startingPrice = TickMath.getSqrtPriceAtTick(targetTick);
            
            tickLower = targetTick - 6000;
            tickUpper = targetTick + 6000;
        }
        
        // Ajustar los ticks para que sean multiplos del tickSpacing
        tickLower = (tickLower / tickSpacing) * tickSpacing;
        tickUpper = (tickUpper / tickSpacing) * tickSpacing;
        
        // Crear la estructura PoolKey
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hookAddress)
        });
        
        bytes memory hookData = new bytes(0);
        
        // Preparar cantidades para liquidez inicial
        uint256 amount0Max = vcopIsToken0 ? vcopLiquidity : stablecoinLiquidity;
        uint256 amount1Max = vcopIsToken0 ? stablecoinLiquidity : vcopLiquidity;
        
        // Calcular la liquidez
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0Max,
            amount1Max
        );
        
        // Preparar parametros de multicall
        bytes[] memory params = new bytes[](2);
        
        // Inicializar pool
        params[0] = abi.encodeWithSelector(
            positionManager.initializePool.selector, 
            poolKey, 
            startingPrice, 
            hookData
        );
        
        // Preparar los parametros para anadir liquidez
        (bytes memory actions, bytes[] memory mintParams) = _mintLiquidityParams(
            poolKey, 
            tickLower, 
            tickUpper, 
            liquidity, 
            amount0Max, 
            amount1Max, 
            deployerAddress,
            hookData
        );
        
        // Anadir liquidez
        params[1] = abi.encodeWithSelector(
            positionManager.modifyLiquidities.selector, 
            abi.encode(actions, mintParams), 
            block.timestamp + 60
        );
        
        // Aprobar los tokens para que PositionManager pueda usarlos
        _approveTokens(address(vcop), usdcAddress, address(positionManager));
        
        // Ejecutar multicall para crear pool y anadir liquidez
        positionManager.multicall(params);
        
        vm.stopBroadcast();
    }
    
    // Funcion auxiliar para codificar los parametros de mint de liquidez
    function _mintLiquidityParams(
        PoolKey memory poolKey,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 liquidity,
        uint256 amount0Max,
        uint256 amount1Max,
        address recipient,
        bytes memory hookData
    ) internal pure returns (bytes memory, bytes[] memory) {
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(poolKey, _tickLower, _tickUpper, liquidity, amount0Max, amount1Max, recipient, hookData);
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
        return (actions, params);
    }
    
    // Aprobar los tokens para Permit2 y PositionManager
    function _approveTokens(address vcopAddress, address usdcAddress, address positionManagerAddress) internal {
        // Aprobar VCOP
        IERC20(vcopAddress).approve(address(PERMIT2), type(uint256).max);
        PERMIT2.approve(vcopAddress, positionManagerAddress, type(uint160).max, type(uint48).max);
        
        // Aprobar USDC
        IERC20(usdcAddress).approve(address(PERMIT2), type(uint256).max);
        PERMIT2.approve(usdcAddress, positionManagerAddress, type(uint160).max, type(uint48).max);
    }
} 