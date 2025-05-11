// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Para ejecutar este script sin verificación de Etherscan:
// forge script script/DeployVCOPComplete.s.sol:DeployVCOPComplete --via-ir --broadcast --rpc-url https://sepolia.base.org --no-verify

import {Script, console} from "forge-std/Script.sol";
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

/**
 * @title DeployVCOPComplete
 * @notice Script para desplegar el sistema VCOP completo en multiples pasos:
 * 1. Desplegar VCOP y Oracle
 * 2. Desplegar Hook (usando HookMiner)
 * 3. Crear pool y anadir liquidez
 */
contract DeployVCOPComplete is Script {
    using CurrencyLibrary for Currency;

    // Constantes de Uniswap V4 - Direcciones oficiales de Base Sepolia
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(address(0x000000000022D473030F116dDEE9F6B43aC78BA3));
    
    // Direccion de USDC en Base Sepolia
    address constant USDC_ADDRESS = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    
    // Parametros configurables para el pool
    uint24 lpFee = 3000; // 0.30%
    int24 tickSpacing = 60;
    uint160 startingPrice = 79228162514264337593543950336; // sqrt(1) * 2^96
    
    // Configuracion para la posicion de liquidez inicial
    uint256 vcopLiquidity = 50 * 1e18; // 50 VCOP
    uint256 stablecoinLiquidity = 50 * 1e6; // 50 USDC (6 decimales)
    int24 tickLower = -600;
    int24 tickUpper = 600;
    
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
        console.log("Verificando red y saldos...");
        console.log("Direccion del desplegador:", deployerAddress);
        
        // Referencia al USDC real en Base Sepolia
        IERC20 usdc = IERC20(USDC_ADDRESS);
        uint256 usdcBalance = usdc.balanceOf(deployerAddress);
        console.log("Saldo USDC del desplegador:", usdcBalance);
        
        // Comprobar si hay suficiente USDC antes de empezar
        require(usdcBalance >= stablecoinLiquidity, "Insuficiente USDC para agregar liquidez. Obtener USDC en faucet de Base Sepolia.");
        
        // Referencias a contratos externos de Uniswap
        IPoolManager poolManager = IPoolManager(poolManagerAddress);
        PositionManager positionManager = PositionManager(payable(positionManagerAddress));
        
        console.log("=== PASO 1: Desplegando VCOP y Oracle ===");
        vm.startBroadcast(deployerPrivateKey);
        
        // Despliegue inicial de VCOP con un suministro de 1,000,000 tokens
        VCOPRebased vcop = new VCOPRebased(1_000_000 * 1e18);
        
        // Despliegue del oraculo con precio inicial de 1 USD
        VCOPOracle oracle = new VCOPOracle(1e18);
        
        console.log("VCOP desplegado en:", address(vcop));
        console.log("Oracle desplegado en:", address(oracle));
        
        vm.stopBroadcast();
        
        // Guardar direcciones para el siguiente script
        vm.setEnv("VCOP_ADDRESS", vm.toString(address(vcop)));
        vm.setEnv("ORACLE_ADDRESS", vm.toString(address(oracle)));
        vm.setEnv("USDC_ADDRESS", vm.toString(USDC_ADDRESS));
        
        console.log("=== PASO 2: Desplegando Hook con HookMiner ===");
        
        // Ejecutar el script para desplegar el hook
        DeployVCOPRebaseHook hookDeployer = new DeployVCOPRebaseHook();
        hookDeployer.run();
        
        // Obtener la direccion del hook desplegado
        address hookAddress = vm.envOr("HOOK_ADDRESS", address(0));
        require(hookAddress != address(0), "Hook address not set");
        
        console.log("=== PASO 3: Creando Pool y anadiendo liquidez ===");
        vm.startBroadcast(deployerPrivateKey);
        
        // Crear Currency para VCOP y USDC
        Currency vcopCurrency = Currency.wrap(address(vcop));
        Currency usdcCurrency = Currency.wrap(USDC_ADDRESS);
        
        // Asegurar que las monedas esten en orden correcto (menor direccion primero)
        Currency currency0;
        Currency currency1;
        bool vcopIsToken0;
        
        if (address(vcop) < USDC_ADDRESS) {
            currency0 = vcopCurrency;
            currency1 = usdcCurrency;
            vcopIsToken0 = true;
        } else {
            currency0 = usdcCurrency;
            currency1 = vcopCurrency;
            vcopIsToken0 = false;
        }
        
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
        _approveTokens(address(vcop), USDC_ADDRESS, address(positionManager));
        
        // Ejecutar multicall para crear pool y anadir liquidez
        positionManager.multicall(params);
        
        console.log("Pool creado y liquidez inicial anadida con exito");
        
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