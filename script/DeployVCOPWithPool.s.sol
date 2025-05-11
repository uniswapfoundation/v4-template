// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

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

import {VCOPRebased} from "../src/VCOPRebased.sol";
import {VCOPOracle} from "../src/VCOPOracle.sol";
import {VCOPRebaseHook} from "../src/VCOPRebaseHook.sol";

/**
 * @title DeployVCOPWithPool
 * @notice Script para desplegar el sistema VCOP completo incluyendo pool y liquidez inicial en Uniswap V4
 */
contract DeployVCOPWithPool is Script {
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
    uint256 vcopLiquidity = 10_000 * 1e18; // 10,000 VCOP
    uint256 stablecoinLiquidity = 10_000 * 1e6; // 10,000 USDC (6 decimales)
    int24 tickLower = -600;
    int24 tickUpper = 600;
    
    // Variables de estado para compartir entre funciones
    IPoolManager poolManager;
    PositionManager positionManager;
    VCOPRebased vcop;
    VCOPOracle oracle;
    VCOPRebaseHook hook;
    IERC20 usdc;
    Currency currency0;
    Currency currency1;
    bool vcopIsToken0;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        address positionManagerAddress = vm.envAddress("POSITION_MANAGER_ADDRESS");
        
        // Referencias a contratos externos de Uniswap
        poolManager = IPoolManager(poolManagerAddress);
        positionManager = PositionManager(payable(positionManagerAddress));
        
        vm.startBroadcast(deployerPrivateKey);
        
        // PASO 1: Desplegar contratos base
        deployBaseContracts();
        
        // PASO 2: Crear el pool en Uniswap V4 y añadir liquidez
        createPoolAndAddLiquidity();
        
        vm.stopBroadcast();
    }
    
    // Función para desplegar los contratos base del sistema VCOP
    function deployBaseContracts() internal {
        console.log("Desplegando contratos VCOP...");
        
        // Referencia al USDC real en Base Sepolia
        usdc = IERC20(USDC_ADDRESS);
        
        // Despliegue inicial de VCOP con un suministro de 1,000,000 tokens
        vcop = new VCOPRebased(1_000_000 * 1e18);
        
        // Despliegue del oraculo con precio inicial de 1 USD
        oracle = new VCOPOracle(1e18);
        
        // Crear Currency para VCOP y USDC
        Currency vcopCurrency = Currency.wrap(address(vcop));
        Currency usdcCurrency = Currency.wrap(USDC_ADDRESS);
        
        // Asegurar que las monedas esten en orden correcto (menor direccion primero)
        if (address(vcop) < USDC_ADDRESS) {
            currency0 = vcopCurrency;
            currency1 = usdcCurrency;
            vcopIsToken0 = true;
        } else {
            currency0 = usdcCurrency;
            currency1 = vcopCurrency;
            vcopIsToken0 = false;
        }
        
        // Despliegue del hook de rebase
        hook = new VCOPRebaseHook(
            poolManager,
            address(vcop),
            address(oracle),
            vcopCurrency,
            usdcCurrency
        );
        
        // Autorizar al hook para ejecutar rebases
        vcop.setRebaser(address(hook), true);
        
        console.log("Contratos base desplegados:");
        console.log("USDC (existente):", USDC_ADDRESS);
        console.log("VCOP Token:", address(vcop));
        console.log("VCOP Oracle:", address(oracle));
        console.log("VCOP Rebase Hook:", address(hook));
        
        // Verificar que tenemos suficiente USDC para agregar liquidez
        uint256 usdcBalance = usdc.balanceOf(msg.sender);
        require(usdcBalance >= stablecoinLiquidity, "Insuficiente USDC para agregar liquidez");
    }
    
    // Función para crear el pool en Uniswap V4 y añadir liquidez
    function createPoolAndAddLiquidity() internal {
        console.log("Creando pool en Uniswap V4...");
        
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: hook // Usar nuestro hook de rebase
        });
        
        bytes memory hookData = new bytes(0);
        
        // Preparar valores de liquidez
        uint256 amount0Max = prepareInitialLiquidity();
        uint256 amount1Max = vcopIsToken0 ? stablecoinLiquidity : vcopLiquidity;
        
        // Calcular la liquidez
        uint128 liquidity = calculateLiquidity(amount0Max, amount1Max);
        
        // Ejecutar la creación del pool y adición de liquidez
        executePoolCreationAndLiquidity(poolKey, hookData, liquidity, amount0Max, amount1Max);
        
        console.log("Pool creado y liquidez inicial anadida con exito");
    }
    
    // Devuelve el valor de amount0Max según la orientación del par
    function prepareInitialLiquidity() internal view returns (uint256) {
        return vcopIsToken0 ? vcopLiquidity : stablecoinLiquidity;
    }
    
    // Calcula la liquidez para los parámetros dados
    function calculateLiquidity(uint256 amount0Max, uint256 amount1Max) internal view returns (uint128) {
        return LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0Max,
            amount1Max
        );
    }
    
    // Ejecuta la creación del pool y añade liquidez
    function executePoolCreationAndLiquidity(
        PoolKey memory poolKey, 
        bytes memory hookData, 
        uint128 liquidity, 
        uint256 amount0Max, 
        uint256 amount1Max
    ) internal {
        // Preparar parámetros de multicall
        bytes[] memory params = new bytes[](2);
        
        // Inicializar pool
        params[0] = abi.encodeWithSelector(
            positionManager.initializePool.selector, 
            poolKey, 
            startingPrice, 
            hookData
        );
        
        // Preparar los parámetros para añadir liquidez y ejecutar
        _prepareAndAddLiquidity(params, poolKey, hookData, liquidity, amount0Max, amount1Max);
    }
    
    // Prepara y ejecuta la adición de liquidez
    function _prepareAndAddLiquidity(
        bytes[] memory params,
        PoolKey memory poolKey, 
        bytes memory hookData, 
        uint128 liquidity, 
        uint256 amount0Max, 
        uint256 amount1Max
    ) internal {
        // Preparar los parámetros para añadir liquidez
        (bytes memory actions, bytes[] memory mintParams) = _mintLiquidityParams(
            poolKey, 
            tickLower, 
            tickUpper, 
            liquidity, 
            amount0Max, 
            amount1Max, 
            msg.sender, 
            hookData
        );
        
        // Añadir liquidez
        params[1] = abi.encodeWithSelector(
            positionManager.modifyLiquidities.selector, 
            abi.encode(actions, mintParams), 
            block.timestamp + 60
        );
        
        // Aprobar los tokens para que PositionManager pueda usarlos
        _approveTokens(address(vcop), USDC_ADDRESS, address(positionManager));
        
        // Ejecutar multicall para crear pool y añadir liquidez
        positionManager.multicall(params);
    }
    
    // Función auxiliar para codificar los parámetros de mint de liquidez
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