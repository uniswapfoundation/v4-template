// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

import {VCOPCollateralized} from "../src/VcopCollateral/VCOPCollateralized.sol";
import {VCOPOracle} from "../src/VcopCollateral/VCOPOracle.sol";
import {VCOPPriceCalculator} from "../src/VcopCollateral/VCOPPriceCalculator.sol";
import {VCOPCollateralManager} from "../src/VcopCollateral/VCOPCollateralManager.sol";
import {VCOPCollateralHook} from "../src/VcopCollateral/VCOPCollateralHook.sol";
import {DeployVCOPCollateralHook} from "./DeployVCOPCollateralHook.s.sol";

// Interfaz simplificada para PositionManager
interface IPositionManager {
    function multicall(bytes[] calldata data) external returns (bytes[] memory);
    function unlock(bytes calldata data) external returns (bytes memory);
    function modifyLiquidities(bytes memory data, uint256 deadline) external returns (bytes memory result);
}

/**
 * @title ConfigureVCOPSystem
 * @notice Script para configurar el sistema VCOP después del despliegue base
 * @dev Para ejecutar: forge script script/ConfigureVCOPSystem.sol:ConfigureVCOPSystem --via-ir --broadcast --fork-url https://sepolia.base.org
 */
contract ConfigureVCOPSystem is Script {
    using CurrencyLibrary for Currency;
    
    // Constantes de Uniswap V4 - Direcciones oficiales de Base Sepolia
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(address(0x000000000022D473030F116dDEE9F6B43aC78BA3));
    
    // Direcciones de contratos desplegados (obtenidas de los logs)
    address constant DEPLOYED_USDC_ADDRESS = 0xF1A811E804b01A113fCE804f2b1C98bE25Ff8557;
    address constant DEPLOYED_VCOP_ADDRESS = 0x7aa903a5fEe8F484575D5B8c43f5516504D29306;
    address constant DEPLOYED_ORACLE_ADDRESS = 0xCE578C179b73b50Eba41b3121a11eB4AeE1EBA7a;
    address constant DEPLOYED_COLLATERAL_MANAGER_ADDRESS = 0x8da23521353163Cb88451a49488c5A287a34EDD3;
    
    // Parametros configurables para el pool
    uint24 lpFee = 3000; // 0.30%
    int24 tickSpacing = 60;
    
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

    // Carga direcciones del despliegue previo
    function loadAddresses() internal view returns (
        address usdcAddress,
        address vcopAddress,
        address oracleAddress,
        address collateralManagerAddress
    ) {
        // Intentar cargar desde variables de entorno
        try vm.envAddress("USDC_ADDRESS") returns (address _usdcAddress) {
            if (_usdcAddress != address(0)) {
                usdcAddress = _usdcAddress;
                console.logString("USDC address cargada de variables de entorno");
            } else {
                usdcAddress = DEPLOYED_USDC_ADDRESS;
                console.logString("USDC address usando valor hardcodeado");
            }
        } catch {
            usdcAddress = DEPLOYED_USDC_ADDRESS;
            console.logString("USDC address usando valor hardcodeado");
        }

        try vm.envAddress("VCOP_ADDRESS") returns (address _vcopAddress) {
            if (_vcopAddress != address(0)) {
                vcopAddress = _vcopAddress;
                console.logString("VCOP address cargada de variables de entorno");
            } else {
                vcopAddress = DEPLOYED_VCOP_ADDRESS;
                console.logString("VCOP address usando valor hardcodeado");
            }
        } catch {
            vcopAddress = DEPLOYED_VCOP_ADDRESS;
            console.logString("VCOP address usando valor hardcodeado");
        }

        try vm.envAddress("ORACLE_ADDRESS") returns (address _oracleAddress) {
            if (_oracleAddress != address(0)) {
                oracleAddress = _oracleAddress;
                console.logString("Oracle address cargada de variables de entorno");
            } else {
                oracleAddress = DEPLOYED_ORACLE_ADDRESS;
                console.logString("Oracle address usando valor hardcodeado");
            }
        } catch {
            oracleAddress = DEPLOYED_ORACLE_ADDRESS;
            console.logString("Oracle address usando valor hardcodeado");
        }

        try vm.envAddress("COLLATERAL_MANAGER_ADDRESS") returns (address _collateralManagerAddress) {
            if (_collateralManagerAddress != address(0)) {
                collateralManagerAddress = _collateralManagerAddress;
                console.logString("CollateralManager address cargada de variables de entorno");
            } else {
                collateralManagerAddress = DEPLOYED_COLLATERAL_MANAGER_ADDRESS;
                console.logString("CollateralManager address usando valor hardcodeado");
            }
        } catch {
            collateralManagerAddress = DEPLOYED_COLLATERAL_MANAGER_ADDRESS;
            console.logString("CollateralManager address usando valor hardcodeado");
        }
        
        // Mostrar las direcciones que se utilizarán
        console.logString("=== Direcciones de contratos ===");
        console.logString("USDC:"); 
        console.logAddress(usdcAddress);
        console.logString("VCOP:"); 
        console.logAddress(vcopAddress);
        console.logString("Oracle:"); 
        console.logAddress(oracleAddress);
        console.logString("CollateralManager:"); 
        console.logAddress(collateralManagerAddress);
        
        // Verificar que todas las direcciones sean válidas
        require(usdcAddress != address(0), "USDC_ADDRESS no valida");
        require(vcopAddress != address(0), "VCOP_ADDRESS no valida");
        require(oracleAddress != address(0), "ORACLE_ADDRESS no valida");
        require(collateralManagerAddress != address(0), "COLLATERAL_MANAGER_ADDRESS no valida");
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        address treasuryAddress = deployerAddress;
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        address positionManagerAddress = vm.envAddress("POSITION_MANAGER_ADDRESS");
        
        // Cargar direcciones del despliegue base
        (
            address usdcAddress,
            address vcopAddress,
            address oracleAddress,
            address collateralManagerAddress
        ) = loadAddresses();
        
        // Cargar contratos desplegados
        IERC20 usdc = IERC20(usdcAddress);
        VCOPCollateralized vcop = VCOPCollateralized(vcopAddress);
        VCOPOracle oracle = VCOPOracle(oracleAddress);
        VCOPCollateralManager collateralManager = VCOPCollateralManager(collateralManagerAddress);
        
        console.logString("=== PASO 1: Desplegando Hook con script especializado ===");
        
        // Guardar direcciones en variables de entorno para el hook
        vm.setEnv("COLLATERAL_MANAGER_ADDRESS", vm.toString(address(collateralManager)));
        vm.setEnv("VCOP_ADDRESS", vm.toString(address(vcop)));
        vm.setEnv("USDC_ADDRESS", vm.toString(address(usdc)));
        vm.setEnv("ORACLE_ADDRESS", vm.toString(address(oracle)));
        
        // Desplegar hook - este deployer será el propietario, evitando problemas de permisos
        DeployVCOPCollateralHook hookDeployer = new DeployVCOPCollateralHook();
        address hookAddress = hookDeployer.run();
        VCOPCollateralHook hook = VCOPCollateralHook(hookAddress);
        
        console.logString("Hook desplegado en:");
        console.logAddress(hookAddress);
        
        // === PASO 2: Configurar Referencias Cruzadas ===
        console.logString("=== PASO 2: Configurando Referencias Cruzadas ===");
        vm.startBroadcast(deployerPrivateKey);
        
        // Verificamos el propietario del hook
        try hook.owner() returns (address hookOwner) {
            console.logString("Owner actual del hook:");
            console.logAddress(hookOwner);
            
            if (hookOwner != deployerAddress) {
                console.logString("ADVERTENCIA: El hook no pertenece al deployer");
                console.logString("Esto debe corregirse manualmente antes de continuar");
                return;
            }
        } catch {
            console.logString("No se pudo verificar el owner del hook");
            return;
        }
        
        // 1. Configurar el hook para que reconozca al collateralManager
        try hook.setCollateralManager(collateralManagerAddress) {
            console.logString("CollateralManager configurado en el hook exitosamente");
        } catch (bytes memory errorData) {
            console.logString("Error al configurar CollateralManager en el hook:");
            console.logBytes(errorData);
            return;
        }
        
        // 2. Configurar el collateralManager para que reconozca al hook
        collateralManager.setPSMHook(hookAddress);
        
        // 3. Token -> Manager
        vcop.setCollateralManager(collateralManagerAddress);
        
        // 4. Permisos de mint/burn al manager
        vcop.setMinter(collateralManagerAddress, true);
        vcop.setBurner(collateralManagerAddress, true);
        
        // 5. Fee collector
        collateralManager.setFeeCollector(treasuryAddress);
        
        // === PASO 3: Configurar Colaterales y Precios ===
        console.logString("=== PASO 3: Configurando Colaterales y Precios ===");
        
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
            vcopAddress,
            usdcAddress,
            lpFee,
            tickSpacing,
            hookAddress,
            4200e6 // Tasa inicial USD/COP
        );
        
        oracle.setPriceCalculator(address(priceCalculator));
        
        console.logString("Colaterales configurados y calculador de precios actualizado");
        
        // === PASO 4: Crear Pool y Añadir Liquidez ===
        console.logString("=== PASO 4: Creando Pool y agregando liquidez ===");
        console.logString("Liquidez USDC a agregar:"); 
        console.logUint(stablecoinLiquidity / 1e6); 
        console.logString("USDC");
        console.logString("Liquidez VCOP a agregar:"); 
        console.logUint(vcopLiquidity / 1e6); 
        console.logString("VCOP");
        console.logString("Ratio VCOP/USDC:"); 
        console.logUint(vcopLiquidity / stablecoinLiquidity);
        
        // Crear Currency para VCOP y USDC
        Currency vcopCurrency = Currency.wrap(vcopAddress);
        Currency usdcCurrency = Currency.wrap(usdcAddress);
        
        // Asegurar que las monedas estén en orden correcto (menor dirección primero)
        Currency currency0;
        Currency currency1;
        bool vcopIsToken0;
        
        // Necesitamos asegurarnos que currency0 tenga dirección menor que currency1
        if (vcopAddress < usdcAddress) {
            // Si VCOP tiene dirección menor, debe ser currency0
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
            // Si USDC tiene dirección menor, debe ser currency0
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
        
        // Inicializar pool directamente con el Pool Manager
        console.logString("Inicializando pool directamente con Pool Manager...");
        
        try IPoolManager(poolManagerAddress).initialize(poolKey, startingPrice) returns (int24 initializedTick) {
            console.logString("Pool inicializado exitosamente");
            console.logString("Tick inicial:");
            console.logInt(initializedTick);
            
            // Ahora añadimos liquidez
            console.logString("Anadiendo liquidez...");
            
            // Aprobar los tokens para que PositionManager pueda usarlos
            _approveTokens(vcopAddress, usdcAddress, positionManagerAddress);
            
            // Siguiendo el patrón exacto de la documentación Uniswap v4:
            // 1. Preparar las acciones para mintear y resolver
            bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));
            
            // 2. Preparar los parámetros de mint
            bytes[] memory mintParams = new bytes[](2);
            mintParams[0] = abi.encode(
                poolKey, 
                tickLower, 
                tickUpper, 
                liquidity, 
                amount0Max, 
                amount1Max, 
                deployerAddress,
                hookData
            );
            mintParams[1] = abi.encode(poolKey.currency0, poolKey.currency1);
            
            // 3. Preparar parámetros para modifyLiquidities
            bytes[] memory params = new bytes[](1);
            uint256 deadline = block.timestamp + 60;
            
            params[0] = abi.encodeWithSelector(
                IPositionManager(positionManagerAddress).modifyLiquidities.selector,
                abi.encode(actions, mintParams),
                deadline
            );
            
            // 4. Ejecutar multicall para añadir liquidez
            try IPositionManager(payable(positionManagerAddress)).multicall(params) {
                console.logString("Liquidez agregada exitosamente");
            } catch (bytes memory errorData) {
                console.logString("Error al agregar liquidez:");
                console.logBytes(errorData);
            }
        } catch (bytes memory errorData) {
            console.logString("Error al inicializar pool:");
            console.logBytes(errorData);
            return;
        }
        
        // === PASO 5: Provisionar Liquidez al Sistema Colateral ===
        console.logString("=== PASO 5: Provisionando Liquidez al Sistema Colateral ===");
        
        // Transferir USDC al collateralManager para el PSM
        usdc.transfer(address(collateralManager), psmUsdcFunding);
        
        // Mint VCOP al collateralManager para el PSM
        vcop.mint(address(collateralManager), psmVcopFunding);
        
        // Activar el módulo PSM en el collateralManager
        collateralManager.setPSMReserveStatus(usdcAddress, true);
        
        // Configurar PSM en el hook
        try hook.updatePSMParameters(
            psmFee, 
            psmVcopFunding / 10 // Limitar operaciones individuales al 10% del fondo
        ) {
            console.logString("Parametros de PSM actualizados exitosamente");
        } catch (bytes memory errorData) {
            console.logString("Error actualizando parametros de PSM:");
            console.logBytes(errorData);
            return;
        }
        
        console.logString("Liquidez provisionada al PSM:");
        console.logString("USDC en PSM:");
        console.logUint(psmUsdcFunding / 1e6);
        console.logString("VCOP en PSM:");
        console.logUint(psmVcopFunding / 1e6);
        
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
        
        // Fix: Check before subtracting to avoid underflow
        if (vcopBalanceAfter >= vcopLiquidity) {
            console.logUint((vcopBalanceAfter - vcopLiquidity) / 1e6);
        } else {
            console.logString("Balance actual menor que liquidez inicial. Balance actual:");
            console.logUint(vcopBalanceAfter / 1e6);
            console.logString("Liquidez inicial:");
            console.logUint(vcopLiquidity / 1e6);
        }
        
        console.logString("Sistema VCOP Colateralizado configurado con exito!");
        
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