// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Para ejecutar este script sin verificacion de Etherscan:
// forge script script/DeployVCOPCollateral.sol:DeployVCOPCollateral --via-ir --broadcast --fork-url https://sepolia.base.org

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
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

import {VCOPCollateralized} from "../src/VcopCollateral/VCOPCollateralized.sol";
import {VCOPOracle} from "../src/VcopCollateral/VCOPOracle.sol";
import {VCOPPriceCalculator} from "../src/VcopCollateral/VCOPPriceCalculator.sol";
import {VCOPCollateralManager} from "../src/VcopCollateral/VCOPCollateralManager.sol";
import {VCOPCollateralHook} from "../src/VcopCollateral/VCOPCollateralHook.sol";
import {DeployMockUSDC} from "./DeployMockUSDC.s.sol";
import {DeployVCOPCollateralHook} from "./DeployVCOPCollateralHook.s.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

/**
 * @title DeployVCOPCollateral
 * @notice Script para desplegar el sistema VCOP colateralizado en multiples pasos:
 * 1. Desplegar USDC Simulado
 * 2. Desplegar VCOP Colateralizado
 * 3. Desplegar Oracle y Calculador de Precios
 * 4. Desplegar Hook (usando HookMiner)
 * 5. Desplegar Collateral Manager
 * 6. Configurar colaterales y permisos
 * 7. Crear pool y añadir liquidez
 * 8. Provisionar liquidez al sistema colateral
 */
contract DeployVCOPCollateral is Script {
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
    uint256 stablecoinLiquidity = 100_000 * 1e6;  // 100,000 USDC
    uint256 vcopLiquidity = 420_000_000 * 1e6;    // 420,000,000 VCOP (ratio 4200:1)
    
    // Configuración para el PSM (Peg Stability Module)
    uint256 psmUsdcFunding = 100_000 * 1e6;      // 100,000 USDC para el PSM
    uint256 psmVcopFunding = 420_000_000 * 1e6;  // 420,000,000 VCOP para el PSM
    uint256 psmFee = 1000;                       // 0.1% fee (base 1e6)
    
    // Parámetros de colateralización
    uint256 collateralRatio = 1500000;           // 150% (1.5 * 1e6)
    uint256 liquidationThreshold = 1200000;      // 120% (1.2 * 1e6)
    uint256 mintFee = 1000;                      // 0.1% (1e6 basis)
    uint256 burnFee = 1000;                      // 0.1% (1e6 basis)
    
    // Ticks para el rango de liquidez
    int24 tickLower;
    int24 tickUpper;
    
    // API Key dummy para evitar errores de verificacion
    string constant DUMMY_API_KEY = "ABCDEFGHIJKLMNOPQRSTUVWXYZ123456";

    // Direcciones internas
    address treasuryAddress;

    function run() public {
        // Establecer una clave de API dummy para Etherscan
        vm.setEnv("ETHERSCAN_API_KEY", DUMMY_API_KEY);
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // Si se proporciona una clave privada específica para el hook owner, usarla
        uint256 hookOwnerPrivateKey = vm.envOr("HOOK_OWNER_PRIVATE_KEY", deployerPrivateKey);
        address deployerAddress = vm.addr(deployerPrivateKey);
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        address positionManagerAddress = vm.envAddress("POSITION_MANAGER_ADDRESS");
        
        // Usar el deployer como treasury inicialmente (se podría cambiar después)
        treasuryAddress = deployerAddress;
        
        // Verificar la red y saldos
        console.logString("Verificando red y saldos...");
        console.logString("Direccion del desplegador:"); 
        console.logAddress(deployerAddress);
        
        // === PASO 1: Desplegar USDC simulado ===
        console.logString("=== PASO 1: Desplegando USDC Simulado ===");
        
        // Desplegar el USDC simulado
        DeployMockUSDC usdcDeployer = new DeployMockUSDC();
        address usdcAddress = usdcDeployer.run();
        
        // Verificar el despliegue
        IERC20 usdc = IERC20(usdcAddress);
        uint256 usdcBalance = usdc.balanceOf(deployerAddress);
        console.logString("Direccion de USDC simulado:"); 
        console.logAddress(usdcAddress);
        console.logString("Saldo USDC del desplegador:"); 
        console.logUint(usdcBalance);
        
        // Comprobar si hay suficiente USDC antes de empezar
        require(usdcBalance >= stablecoinLiquidity + psmUsdcFunding, "Insuficiente USDC para el sistema completo.");
        
        // Referencias a contratos externos de Uniswap
        IPoolManager poolManager = IPoolManager(poolManagerAddress);
        PositionManager positionManager = PositionManager(payable(positionManagerAddress));
        
        // === PASO 2: Desplegar VCOP Colateralizado ===
        console.logString("=== PASO 2: Desplegando VCOP Colateralizado ===");
        vm.startBroadcast(deployerPrivateKey);
        
        // Despliegue de VCOP Colateralizado
        VCOPCollateralized vcop = new VCOPCollateralized();
        
        console.logString("VCOP Colateralizado desplegado en:"); 
        console.logAddress(address(vcop));
        
        vm.stopBroadcast();
        
        // === PASO 3: Desplegar Oracle y Calculador de Precios ===
        console.logString("=== PASO 3: Desplegando Oracle y Calculador de Precios ===");
        vm.startBroadcast(deployerPrivateKey);
        
        // Despliegue del oráculo con tasa inicial de 4200 COP = 1 USD
        VCOPOracle oracle = new VCOPOracle(
            initialUsdToCopRate,
            poolManagerAddress,
            address(vcop),
            usdcAddress,
            lpFee,
            tickSpacing,
            address(0) // Hook se configurará después
        );
        
        console.logString("Oracle desplegado en:"); 
        console.logAddress(address(oracle));
        console.logString("Tasa inicial USD/COP:");
        console.logUint(initialUsdToCopRate / 1e6);
        
        vm.stopBroadcast();
        
        // Guardar direcciones para el siguiente script
        vm.setEnv("VCOP_ADDRESS", vm.toString(address(vcop)));
        vm.setEnv("ORACLE_ADDRESS", vm.toString(address(oracle)));
        vm.setEnv("USDC_ADDRESS", vm.toString(usdcAddress));
        
        // === PASO 5: Desplegar VCOPCollateralManager ===
        console.logString("=== PASO 5: Desplegando Collateral Manager ===");
        vm.startBroadcast(deployerPrivateKey);
        
        // Desplegar el gestor de colateral
        VCOPCollateralManager collateralManager = new VCOPCollateralManager(
            address(vcop),
            address(oracle)
        );
        
        console.logString("Collateral Manager desplegado en:");
        console.logAddress(address(collateralManager));
        
        vm.stopBroadcast();
        
        // Guardar dirección del manager para que el hook pueda usarla durante el despliegue
        vm.setEnv("COLLATERAL_MANAGER_ADDRESS", vm.toString(address(collateralManager)));
        
        // === PASO 4: Desplegar Hook con script especializado ===
        console.logString("=== PASO 4: Desplegando Hook con script especializado ===");
        
        // Ejecutar el script específico para desplegar el hook
        DeployVCOPCollateralHook hookDeployer = new DeployVCOPCollateralHook();
        address hookAddress = hookDeployer.run();
        
        // Obtener la referencia al hook desplegado
        VCOPCollateralHook hook = VCOPCollateralHook(hookAddress);
        
        console.logString("Hook desplegado en:");
        console.logAddress(address(hook));
        
        // Guardar dirección del hook para futuros scripts
        vm.setEnv("HOOK_ADDRESS", vm.toString(address(hook)));
        
        // === PASO 6: Configurar Referencias Cruzadas ===
        console.logString("=== PASO 6: Configurando Referencias Cruzadas ===");
        vm.startBroadcast(deployerPrivateKey);
        
        // Verificar el propietario actual del hook
        address hookOwner;
        try hook.owner() returns (address currentOwner) {
            hookOwner = currentOwner;
            console.logString("Owner actual del hook:");
            console.logAddress(hookOwner);
            
            // Transferir la propiedad al deployer si es necesario
            if (hookOwner != deployerAddress) {
                console.logString("Transfiriendo propiedad del hook al deployer...");
                
                // Primero necesitamos transmitir desde la dirección del owner actual
                vm.stopBroadcast();
                vm.startBroadcast(hookOwnerPrivateKey);
                
                // Transferir propiedad al deployer
                hook.transferOwnership(deployerAddress);
                console.logString("Propiedad transferida al deployer");
                
                // Volver al deployer
                vm.stopBroadcast();
                vm.startBroadcast(deployerPrivateKey);
            }
        } catch {
            console.logString("No se pudo obtener el owner del hook, posiblemente no es Ownable");
        }
        
        // 1. Configurar el hook para que reconozca al collateralManager (si no se hizo en el constructor)
        if (hook.collateralManagerAddress() == address(0)) {
            try hook.setCollateralManager(address(collateralManager)) {
                console.logString("CollateralManager asignado al hook exitosamente");
            } catch (bytes memory errorData) {
                console.logString("Error al asignar CollateralManager al hook:");
                console.logBytes(errorData);
            }
        } else {
            console.logString("Hook ya tiene CollateralManager configurado:");
            console.logAddress(hook.collateralManagerAddress());
        }
        
        // 2. Configurar el collateralManager para que reconozca al hook
        collateralManager.setPSMHook(address(hook));
        
        // 3. Token -> Manager
        vcop.setCollateralManager(address(collateralManager));
        
        // 4. Permisos de mint/burn al manager
        vcop.setMinter(address(collateralManager), true);
        vcop.setBurner(address(collateralManager), true);
        
        // 5. Fee collector
        collateralManager.setFeeCollector(treasuryAddress);
        
        vm.stopBroadcast();
        
        // === PASO 7: Configurar Colaterales y Permisos ===
        console.logString("=== PASO 7: Configurando Colaterales y Permisos ===");
        vm.startBroadcast(deployerPrivateKey);
        
        // Configurar USDC como colateral
        collateralManager.configureCollateral(
            usdcAddress,
            collateralRatio, // 150%
            mintFee,         // 0.1%
            burnFee,         // 0.1%
            liquidationThreshold, // 120%
            true // activo
        );
        
        // Registrar identificador para despliegue automatizado
        collateralManager.registerTokenIdentifier(usdcAddress, "USDC");
        
        // Actualizar calculador de precios con dirección del hook
        VCOPPriceCalculator priceCalculator = new VCOPPriceCalculator(
            poolManagerAddress,
            address(vcop),
            usdcAddress,
            lpFee,
            tickSpacing,
            address(hook),
            initialUsdToCopRate
        );
        
        oracle.setPriceCalculator(address(priceCalculator));
        
        console.logString("Colateral USDC configurado con ratio:");
        console.logUint(collateralRatio);
        console.logString("Threshold de liquidacion:");
        console.logUint(liquidationThreshold);
        console.logString("Calculador de precios actualizado en:");
        console.logAddress(address(priceCalculator));
        
        vm.stopBroadcast();
        
        // === PASO 8: Crear Pool y Añadir Liquidez ===
        console.logString("=== PASO 8: Creando Pool y agregando liquidez ===");
        console.logString("Liquidez USDC a agregar:"); 
        console.logUint(stablecoinLiquidity / 1e6); 
        console.logString("USDC");
        console.logString("Liquidez VCOP a agregar:"); 
        console.logUint(vcopLiquidity / 1e6); 
        console.logString("VCOP");
        console.logString("Ratio VCOP/USDC:"); 
        console.logUint(vcopLiquidity / stablecoinLiquidity);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Crear Currency para VCOP y USDC
        Currency vcopCurrency = Currency.wrap(address(vcop));
        Currency usdcCurrency = Currency.wrap(usdcAddress);
        
        // Asegurar que las monedas estén en orden correcto (menor dirección primero)
        Currency currency0;
        Currency currency1;
        bool vcopIsToken0;
        
        if (address(vcop) < usdcAddress) {
            currency0 = vcopCurrency;
            currency1 = usdcCurrency;
            vcopIsToken0 = true;
            
            // Si VCOP es token0, entonces para una relación de 4200 VCOP = 1 USDC
            // El precio debe ser bajo (1/4200)
            int24 targetTick = -83000;
            startingPrice = TickMath.getSqrtPriceAtTick(targetTick);
            
            // Para VCOP/USDC, ampliamos el rango de ticks
            tickLower = targetTick - 6000; 
            tickUpper = targetTick + 6000;
            
        } else {
            currency0 = usdcCurrency;
            currency1 = vcopCurrency;
            vcopIsToken0 = false;
            
            // Si USDC es token0, entonces para una relación de 4200 VCOP = 1 USDC
            // El precio debe ser alto (4200)
            int24 targetTick = 83000;
            startingPrice = TickMath.getSqrtPriceAtTick(targetTick);
            
            // Para USDC/VCOP, ampliamos el rango de ticks
            tickLower = targetTick - 6000;
            tickUpper = targetTick + 6000;
        }
        
        // Ajustar los ticks para que sean múltiplos del tickSpacing
        tickLower = (tickLower / tickSpacing) * tickSpacing;
        tickUpper = (tickUpper / tickSpacing) * tickSpacing;
        
        console.logString("VCOP es token0:");
        console.logBool(vcopIsToken0);
        console.logString("Precio inicial:");
        console.logUint(uint256(startingPrice));
        console.logString("Tick inferior:");
        console.logInt(tickLower);
        console.logString("Tick superior:");
        console.logInt(tickUpper);
        
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
        
        console.logString("Cantidad maxima token0:");
        console.logUint(amount0Max);
        console.logString("Cantidad maxima token1:");
        console.logUint(amount1Max);
        
        // Mint VCOP para el deployer para añadir liquidez
        vcop.mint(deployerAddress, vcopLiquidity);
        
        // Calcular la liquidez
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0Max,
            amount1Max
        );
        
        console.logString("Liquidez calculada:");
        console.logUint(uint256(liquidity));
        
        // Preparar parámetros de multicall
        bytes[] memory params = new bytes[](2);
        
        // Inicializar pool
        params[0] = abi.encodeWithSelector(
            positionManager.initializePool.selector, 
            poolKey, 
            startingPrice, 
            hookData
        );
        
        // Preparar los parámetros para añadir liquidez
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
        
        // Añadir liquidez
        params[1] = abi.encodeWithSelector(
            positionManager.modifyLiquidities.selector, 
            abi.encode(actions, mintParams), 
            block.timestamp + 60
        );
        
        // Aprobar los tokens para que PositionManager pueda usarlos
        _approveTokens(address(vcop), usdcAddress, address(positionManager));
        
        // Ejecutar multicall para crear pool y añadir liquidez
        positionManager.multicall(params);
        
        // Verificar balances después de añadir liquidez
        uint256 vcopBalanceDeployer = vcop.balanceOf(deployerAddress);
        uint256 usdcBalanceDeployer = usdc.balanceOf(deployerAddress);
        
        console.logString("Balance VCOP del desplegador despues de agregar liquidez:");
        console.logUint(vcopBalanceDeployer);
        console.logString("Balance USDC del desplegador despues de agregar liquidez:");
        console.logUint(usdcBalanceDeployer);
        
        console.logString("Pool creado y liquidez inicial agregada con exito");
        
        vm.stopBroadcast();
        
        // === PASO 9: Provisionar Liquidez al Sistema Colateral ===
        console.logString("=== PASO 9: Provisionando Liquidez al Sistema Colateral ===");
        vm.startBroadcast(deployerPrivateKey);
        
        // Transferir USDC al collateralManager para el PSM
        usdc.transfer(address(collateralManager), psmUsdcFunding);
        
        // Mint VCOP al collateralManager para el PSM
        vcop.mint(address(collateralManager), psmVcopFunding);
        
        // Activar el módulo PSM en el collateralManager
        collateralManager.setPSMReserveStatus(usdcAddress, true);
        
        // Verificar nuevamente el propietario del hook
        try hook.owner() returns (address currentOwner) {
            console.logString("Owner actual del hook en paso 9:");
            console.logAddress(currentOwner);
            
            if (currentOwner != deployerAddress) {
                console.logString("ADVERTENCIA: Hook no pertenece al deployer");
                // No podemos usar HOOK_OWNER_PRIVATE_KEY aqui porque ya usamos el PSM
                // Reportar el problema para que se solucione manualmente
            }
        } catch {
            console.logString("No se pudo verificar el propietario del hook");
        }
        
        // Verificar que el hook tenga permisos adecuados
        // Asegurar que el hook reconozca al manager
        try hook.collateralManagerAddress() returns (address currentManager) {
            console.logString("CollateralManager actual del hook:");
            console.logAddress(currentManager);
            
            if (currentManager != address(collateralManager)) {
                console.logString("Intentando actualizar el CollateralManager en el hook...");
                try hook.setCollateralManager(address(collateralManager)) {
                    console.logString("CollateralManager actualizado en el hook exitosamente");
                } catch (bytes memory errorData) {
                    console.logString("Error al actualizar CollateralManager en el hook:");
                    console.logBytes(errorData);
                    console.logString("Esto puede deberse a un problema de permisos");
                }
            } else {
                console.logString("Hook ya tiene el CollateralManager configurado correctamente");
            }
        } catch {
            console.logString("No se pudo verificar el CollateralManager en el hook");
        }
        
        // Configurar PSM en el hook
        try hook.updatePSMParameters(
            psmFee, 
            psmVcopFunding / 10 // Limitar operaciones individuales al 10% del fondo
        ) {
            console.logString("Parametros de PSM actualizados exitosamente");
        } catch (bytes memory errorData) {
            console.logString("Error actualizando parametros de PSM:");
            console.logBytes(errorData);
            
            // En caso de error, verificar el owner del hook
            try hook.owner() returns (address hookOwner) {
                console.logString("Owner del hook:");
                console.logAddress(hookOwner);
                
                console.logString("Deployer address:");
                console.logAddress(deployerAddress);
                
                if (hookOwner != deployerAddress) {
                    console.logString("El propietario del hook no es el deployer. Esto debe corregirse manualmente.");
                }
            } catch {
                console.logString("No se pudo obtener el owner del hook");
            }
        }
        
        console.logString("Liquidez provisionada al PSM:");
        console.logString("USDC en PSM:");
        console.logUint(psmUsdcFunding / 1e6);
        console.logString("VCOP en PSM:");
        console.logUint(psmVcopFunding / 1e6);
        
        // Verificar precios y paridad
        console.logString("=== Verificacion Final de Precios ===");
        
        try priceCalculator.calculateAllPrices() returns (
            uint256 vcopToUsdPrice, 
            uint256 vcopToCopPrice, 
            int24 currentTick, 
            bool parityStatus
        ) {
            console.logString("Precio VCOP/USDC calculado:");
            console.logUint(vcopToUsdPrice / 1e6);
            console.logString("Precio VCOP/COP calculado:");
            console.logUint(vcopToCopPrice / 1e6);
            console.logString("Tick actual del pool:");
            console.logInt(currentTick);
            console.logString("VCOP en paridad 1:1 con COP?");
            console.logBool(parityStatus);
        } catch {
            console.logString("No se pudieron calcular todos los precios. El pool necesita tiempo para inicializarse completamente.");
        }
        
        // Crear una posición de prueba con colateral
        console.logString("=== Creando Posicion de Prueba ===");
        
        // Aprobar USDC para el collateralManager
        uint256 testCollateralAmount = 1000 * 1e6; // 1000 USDC
        usdc.approve(address(collateralManager), testCollateralAmount);
        
        // Calcular VCOP máximo para este colateral
        uint256 maxVcop = collateralManager.getMaxVCOPforCollateral(usdcAddress, testCollateralAmount);
        console.logString("VCOP maximo para 1000 USDC de colateral:");
        console.logUint(maxVcop / 1e6);
        
        // Crear posición
        collateralManager.createPosition(usdcAddress, testCollateralAmount, maxVcop);
        
        // Verificar VCOP recibido
        uint256 vcopBalanceAfter = vcop.balanceOf(deployerAddress);
        console.logString("VCOP recibido por colateralizacion:");
        console.logUint((vcopBalanceAfter - vcopBalanceDeployer) / 1e6);
        
        console.logString("Sistema VCOP Colateralizado desplegado con exito!");
        
        vm.stopBroadcast();
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