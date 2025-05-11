// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Para ejecutar este script sin verificacion de Etherscan:
// forge script script/DeployVCOPComplete.fixed.sol:DeployVCOPComplete --via-ir --broadcast --fork-url https://sepolia.base.org

import {Script} from "forge-std/Script.sol";
import "forge-std/Test.sol"; // Importar Test en lugar de console2 directamente
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

/**
 * @title DeployVCOPComplete
 * @notice Script para desplegar el sistema VCOP completo en multiples pasos:
 * 1. Desplegar USDC Simulado
 * 2. Desplegar VCOP y Oracle
 * 3. Desplegar Hook (usando HookMiner)
 * 4. Crear pool y anadir liquidez
 */
contract DeployVCOPComplete is Script {
    using CurrencyLibrary for Currency;

    // Constantes de Uniswap V4 - Direcciones oficiales de Base Sepolia
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(address(0x000000000022D473030F116dDEE9F6B43aC78BA3));
    
    // Parametros configurables para el pool
    uint24 lpFee = 3000; // 0.30%
    int24 tickSpacing = 60;
    
    // Tasa inicial USD/COP (4200 COP = 1 USD)
    uint256 initialUsdToCopRate = 4200e6; // Ahora con 6 decimales
    
    // Para una relacion 1:4200, usamos un precio inicial adecuado
    // La relacion 1:4200 significa 4200 VCOP = 1 USDC
    uint160 startingPrice;
    
    // Configuración para la posición de liquidez inicial (ACTUALIZADA)
    // 100,000 USDC con 6 decimales
    uint256 stablecoinLiquidity = 100_000 * 1e6; 
    
    // Mantener proporción 4200:1 -> 420,000,000 VCOP
    uint256 vcopLiquidity = 420_000_000 * 1e6; 
    
    // Usar ticks mas amplios para acomodar la relacion 1:4200
    int24 tickLower;
    int24 tickUpper;
    
    // API Key dummy para evitar errores de verificacion
    string constant DUMMY_API_KEY = "ABCDEFGHIJKLMNOPQRSTUVWXYZ123456";

    function run() public {
        // Establecer una clave de API dummy para Etherscan
        vm.setEnv("ETHERSCAN_API_KEY", DUMMY_API_KEY);
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        address positionManagerAddress = vm.envAddress("POSITION_MANAGER_ADDRESS");
        
        // Verificar la red y saldos
        Test.log("Verificando red y saldos...");
        Test.log("Direccion del desplegador:", deployerAddress);
        
        // === PASO 1: Desplegar USDC simulado ===
        Test.log("=== PASO 1: Desplegando USDC Simulado ===");
        
        // Desplegar el USDC simulado
        DeployMockUSDC usdcDeployer = new DeployMockUSDC();
        address usdcAddress = usdcDeployer.run();
        
        // Verificar el despliegue
        IERC20 usdc = IERC20(usdcAddress);
        uint256 usdcBalance = usdc.balanceOf(deployerAddress);
        Test.log("Direccion de USDC simulado:", usdcAddress);
        Test.log("Saldo USDC del desplegador:", usdcBalance);
        
        // Comprobar si hay suficiente USDC antes de empezar
        require(usdcBalance >= stablecoinLiquidity, "Insuficiente USDC para agregar liquidez.");
        
        // Referencias a contratos externos de Uniswap
        IPoolManager poolManager = IPoolManager(poolManagerAddress);
        PositionManager positionManager = PositionManager(payable(positionManagerAddress));
        
        Test.log("=== PASO 2: Desplegando VCOP y Oracle ===");
        vm.startBroadcast(deployerPrivateKey);
        
        // Despliegue inicial de VCOP con un suministro de 1,000,000,000 tokens (ACTUALIZADO)
        VCOPRebased vcop = new VCOPRebased(1_000_000_000 * 1e6); // 1000M con 6 decimales
        
        // Despliegue del oraculo con tasa inicial de 4200 COP = 1 USD
        VCOPOracle oracle = new VCOPOracle(initialUsdToCopRate);
        
        Test.log("VCOP desplegado en:", address(vcop));
        Test.log("Oracle desplegado en:", address(oracle));
        Test.log("Tasa inicial USD/COP:", initialUsdToCopRate / 1e6);
        Test.log("Suministro inicial de VCOP:", 1_000_000_000);
        
        vm.stopBroadcast();
        
        // Guardar direcciones para el siguiente script
        vm.setEnv("VCOP_ADDRESS", vm.toString(address(vcop)));
        vm.setEnv("ORACLE_ADDRESS", vm.toString(address(oracle)));
        vm.setEnv("USDC_ADDRESS", vm.toString(usdcAddress));
        
        Test.log("=== PASO 3: Desplegando Hook con HookMiner ===");
        
        // Ejecutar el script para desplegar el hook
        DeployVCOPRebaseHook hookDeployer = new DeployVCOPRebaseHook();
        hookDeployer.run();
        
        // Obtener la direccion del hook desplegado
        address hookAddress = vm.envOr("HOOK_ADDRESS", address(0));
        require(hookAddress != address(0), "Hook address not set");
        
        Test.log("=== PASO 4: Creando Pool y anadiendo liquidez ===");
        Test.log("Liquidez USDC a agregar:", stablecoinLiquidity / 1e6, "USDC");
        Test.log("Liquidez VCOP a agregar:", vcopLiquidity / 1e6, "VCOP");
        Test.log("Ratio VCOP/USDC:", vcopLiquidity / stablecoinLiquidity);
        
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
            // El precio debe ser bajo (1/4200)
            // Log base 1.0001 de (1/4200) ≈ -83
            int24 targetTick = -83000;
            startingPrice = TickMath.getSqrtPriceAtTick(targetTick);
            
            // Para VCOP/USDC, ampliamos el rango de ticks para acomodar la relacion
            tickLower = targetTick - 6000; // Rango amplio por debajo
            tickUpper = targetTick + 6000; // Rango amplio por encima
            
        } else {
            currency0 = usdcCurrency;
            currency1 = vcopCurrency;
            vcopIsToken0 = false;
            
            // Si USDC es token0, entonces para una relacion de 4200 VCOP = 1 USDC
            // El precio debe ser alto (4200)
            // Log base 1.0001 de 4200 ≈ 83
            int24 targetTick = 83000;
            startingPrice = TickMath.getSqrtPriceAtTick(targetTick);
            
            // Para USDC/VCOP, ampliamos el rango de ticks para acomodar la relacion
            tickLower = targetTick - 6000; // Rango amplio por debajo
            tickUpper = targetTick + 6000; // Rango amplio por encima
        }
        
        // Ajustar los ticks para que sean multiplos del tickSpacing
        tickLower = (tickLower / tickSpacing) * tickSpacing;
        tickUpper = (tickUpper / tickSpacing) * tickSpacing;
        
        Test.log("VCOP es token0:", vcopIsToken0);
        Test.log("Precio inicial:", uint256(startingPrice));
        Test.log("Tick inferior:", tickLower);
        Test.log("Tick superior:", tickUpper);
        
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
        
        Test.log("Cantidad maxima token0:", amount0Max);
        Test.log("Cantidad maxima token1:", amount1Max);
        
        // Calcular la liquidez
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0Max,
            amount1Max
        );
        
        Test.log("Liquidez calculada:", uint256(liquidity));
        
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
        
        // Verificar balances finales
        uint256 vcopBalanceDeployer = vcop.balanceOf(deployerAddress);
        uint256 usdcBalanceDeployer = usdc.balanceOf(deployerAddress);
        
        Test.log("Balance final VCOP del desplegador:", vcopBalanceDeployer);
        Test.log("Balance final USDC del desplegador:", usdcBalanceDeployer);
        
        Test.log("Pool creado y liquidez inicial anadida con exito");
        
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