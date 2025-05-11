// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
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

/**
 * @title CreatePoolAndAddLiquidity
 * @notice Script para crear el pool VCOP/USDC con los contratos ya desplegados
 * y aniadir liquidez inicial con solo 50 USDC
 */
contract CreatePoolAndAddLiquidity is Script {
    using CurrencyLibrary for Currency;

    // Constantes de Uniswap V4 - Direcciones oficiales de Base Sepolia
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(address(0x000000000022D473030F116dDEE9F6B43aC78BA3));
    
    // Parametros configurables para el pool
    uint24 lpFee = 3000; // 0.30%
    int24 tickSpacing = 60;
    uint160 startingPrice = 79228162514264337593543950336; // sqrt(1) * 2^96
    
    // Configuracion para la posicion de liquidez inicial
    uint256 vcopLiquidity = 50 * 1e18; // 50 VCOP
    uint256 stablecoinLiquidity = 50 * 1e6; // 50 USDC (6 decimales)
    int24 tickLower = -600;
    int24 tickUpper = 600;
    
    // Variables para almacenar direcciones y contratos
    address vcopAddress;
    address usdcAddress;
    address hookAddress;
    IPoolManager poolManager;
    PositionManager positionManager;
    IERC20 vcop;
    IERC20 usdc;
    bool vcopIsToken0;
    Currency currency0;
    Currency currency1;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Cargar direcciones desde .env
        _loadAddresses();
        
        // Iniciar broadcast
        vm.startBroadcast(deployerPrivateKey);
        
        // Verificar balances
        _checkBalances();
        
        // Crear PoolKey
        PoolKey memory poolKey = _createPoolKey();
        
        // Inicializar pool y agregar liquidez
        _initializePoolAndAddLiquidity(poolKey);
        
        vm.stopBroadcast();
    }
    
    function _loadAddresses() internal {
        // Cargar direcciones desde .env
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        address positionManagerAddress = vm.envAddress("POSITION_MANAGER_ADDRESS");
        vcopAddress = vm.envAddress("VCOP_ADDRESS");
        hookAddress = vm.envAddress("HOOK_ADDRESS");
        usdcAddress = vm.envAddress("USDC_ADDRESS");
        
        // Referencias a contratos
        poolManager = IPoolManager(poolManagerAddress);
        positionManager = PositionManager(payable(positionManagerAddress));
        vcop = IERC20(vcopAddress);
        usdc = IERC20(usdcAddress);
        
        console.log("=== Usando contratos ya desplegados ===");
        console.log("VCOP:", vcopAddress);
        console.log("Hook:", hookAddress);
        console.log("USDC:", usdcAddress);
        console.log("PoolManager:", poolManagerAddress);
        console.log("PositionManager:", positionManagerAddress);
    }
    
    function _checkBalances() internal {
        // Crear Currency para VCOP y USDC
        Currency vcopCurrency = Currency.wrap(vcopAddress);
        Currency usdcCurrency = Currency.wrap(usdcAddress);
        
        // Determinar orden de tokens
        if (vcopAddress < usdcAddress) {
            currency0 = vcopCurrency;
            currency1 = usdcCurrency;
            vcopIsToken0 = true;
            console.log("VCOP es token0");
        } else {
            currency0 = usdcCurrency;
            currency1 = vcopCurrency;
            vcopIsToken0 = false;
            console.log("USDC es token0");
        }
        
        // Verificar balances
        uint256 usdcBalance = usdc.balanceOf(msg.sender);
        uint256 vcopBalance = vcop.balanceOf(msg.sender);
        
        console.log("Saldo USDC disponible:", usdcBalance);
        console.log("Saldo VCOP disponible:", vcopBalance);
        console.log("USDC necesario:", stablecoinLiquidity);
        console.log("VCOP necesario:", vcopLiquidity);
        
        require(usdcBalance >= stablecoinLiquidity, "Insuficiente USDC para agregar liquidez");
        require(vcopBalance >= vcopLiquidity, "Insuficiente VCOP para agregar liquidez");
    }
    
    function _createPoolKey() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hookAddress)
        });
    }
    
    function _initializePoolAndAddLiquidity(PoolKey memory poolKey) internal {
        console.log("=== Creando Pool y aniadiendo liquidez ===");
        
        // Data para inicialización
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
        
        // Aprobar tokens
        _approveTokens(vcopAddress, usdcAddress, address(positionManager));
        
        // Primera transacción: Inicializar pool
        _initializePool(poolKey);
        
        // Segunda transacción: Añadir liquidez
        _addLiquidity(poolKey, liquidity, amount0Max, amount1Max, hookData);
        
        console.log("Pool creado y liquidez inicial aniadida con exito");
    }
    
    function _initializePool(PoolKey memory poolKey) internal {
        bytes memory initializePoolCalldata = abi.encodeWithSelector(
            positionManager.initializePool.selector,
            poolKey,
            startingPrice,
            new bytes(0)
        );
        
        (bool success, ) = address(positionManager).call(initializePoolCalldata);
        require(success, "Pool initialization failed");
        console.log("Pool inicializado con exito");
    }
    
    function _addLiquidity(
        PoolKey memory poolKey,
        uint128 liquidity,
        uint256 amount0Max,
        uint256 amount1Max,
        bytes memory hookData
    ) internal {
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
        
        bytes memory addLiquidityCalldata = abi.encodeWithSelector(
            positionManager.modifyLiquidities.selector,
            abi.encode(actions, mintParams),
            block.timestamp + 60
        );
        
        (bool success, ) = address(positionManager).call(addLiquidityCalldata);
        require(success, "Adding liquidity failed");
        console.log("Liquidez aniadida con exito");
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