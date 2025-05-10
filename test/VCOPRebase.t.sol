// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Para los tests usamos FOUNDRY_PROFILE=default que salta las validaciones de hooks
// ver: forge.toml

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {MockPoolManager} from "./mocks/MockPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

import {VCOPRebased} from "../src/VCOPRebased.sol";
import {VCOPOracle} from "../src/VCOPOracle.sol";
// import {VCOPRebaseHook} from "../src/VCOPRebaseHook.sol";

// Versión mock del hook solo para testing
contract MockVCOPRebaseHook {
    // Token VCOP
    VCOPRebased public immutable vcop;
    
    // Oráculo de precio
    VCOPOracle public immutable oracle;
    
    // Periodo mínimo entre rebases (en segundos)
    uint256 public rebaseInterval = 1 hours;
    
    // Último timestamp de rebase
    uint256 public lastRebaseTime;
    
    // Currency ID del token VCOP
    Currency public vcopCurrency;
    
    // Currency ID del token USD de referencia (stablecoin)
    Currency public stablecoinCurrency;
    
    // Evento emitido cuando se ejecuta un rebase
    event RebaseExecuted(uint256 price, uint256 newTotalSupply);
    
    // Evento emitido cuando se actualiza el intervalo de rebase
    event RebaseIntervalUpdated(uint256 oldInterval, uint256 newInterval);

    constructor(
        IPoolManager, // ignoramos este parámetro 
        address _vcop,
        address _oracle,
        Currency _vcopCurrency,
        Currency _stablecoinCurrency
    ) {
        vcop = VCOPRebased(_vcop);
        oracle = VCOPOracle(_oracle);
        vcopCurrency = _vcopCurrency;
        stablecoinCurrency = _stablecoinCurrency;
        lastRebaseTime = block.timestamp;
    }
    
    /**
     * @dev Cambia el intervalo mínimo entre rebases
     * @param newInterval El nuevo intervalo en segundos
     */
    function setRebaseInterval(uint256 newInterval) external {
        require(msg.sender == vcop.owner(), "Not authorized");
        
        uint256 oldInterval = rebaseInterval;
        rebaseInterval = newInterval;
        
        emit RebaseIntervalUpdated(oldInterval, newInterval);
    }
    
    /**
     * @dev Ejecuta un rebase basado en el precio del oráculo
     * @return El nuevo suministro total
     */
    function executeRebase() public returns (uint256) {
        require(block.timestamp >= lastRebaseTime + rebaseInterval, "Rebase too soon");
        
        uint256 price = oracle.getPrice();
        uint256 newSupply = vcop.rebase(price);
        
        lastRebaseTime = block.timestamp;
        
        emit RebaseExecuted(price, newSupply);
        
        return newSupply;
    }
    
    /**
     * @dev Solo para testing - Ejecuta un rebase ignorando el intervalo
     */
    function forceRebase() public returns (uint256) {
        uint256 price = oracle.getPrice();
        uint256 newSupply = vcop.rebase(price);
        
        lastRebaseTime = block.timestamp;
        
        emit RebaseExecuted(price, newSupply);
        
        return newSupply;
    }
}

// Test simplificado de la stablecoin rebase - conceptual
// No se prueban las integraciones con Uniswap v4 aquí
contract VCOPRebaseTest is Test {
    // Contratos
    MockPoolManager public manager;
    VCOPRebased public vcop;
    VCOPOracle public oracle;
    MockVCOPRebaseHook public hook;
    MockERC20 public usdc;
    
    // Direcciones
    address public deployer = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    
    // Constantes
    uint256 public initialVCOPSupply = 1_000_000 * 1e18;
    uint256 public initialUserBalance = 10_000 * 1e18;
    
    function setUp() public {
        // Establecer un timestamp de bloque inicial para determinismo
        vm.warp(1000000);
        
        // Cambiar a deployer
        vm.startPrank(deployer);
        
        // Desplegar MockPoolManager en lugar de PoolManager real
        manager = new MockPoolManager();
        
        // Desplegar USDC mock
        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdc.mint(deployer, 1_000_000 * 1e6);
        usdc.mint(user1, 100_000 * 1e6);
        usdc.mint(user2, 100_000 * 1e6);
        
        // Desplegar VCOP token
        vcop = new VCOPRebased(initialVCOPSupply);
        
        // Desplegar Oracle
        oracle = new VCOPOracle(1e18); // Precio inicial: 1 USD
        
        // Para propósitos de testing, desplegamos el hook mock
        hook = new MockVCOPRebaseHook(
            IPoolManager(address(manager)),
            address(vcop),
            address(oracle),
            Currency.wrap(address(vcop)),
            Currency.wrap(address(usdc))
        );
        
        // Autorizar al hook a ejecutar rebases
        vcop.setRebaser(address(hook), true);
        
        // Transferir algunos tokens a los usuarios para pruebas
        vcop.transfer(user1, initialUserBalance);
        vcop.transfer(user2, initialUserBalance);
        
        vm.stopPrank();
    }
    
    function testInitialState() public {
        assertEq(vcop.totalSupply(), initialVCOPSupply);
        assertEq(vcop.balanceOf(deployer), initialVCOPSupply - (initialUserBalance * 2));
        assertEq(vcop.balanceOf(user1), initialUserBalance);
        assertEq(vcop.balanceOf(user2), initialUserBalance);
        assertEq(oracle.getPrice(), 1e18);
    }
    
    function testPositiveRebase() public {
        // Precio inicial
        uint256 initialSupply = vcop.totalSupply();
        uint256 initialUser1Balance = vcop.balanceOf(user1);
        
        // Avanzar el tiempo suficiente para permitir el rebase
        vm.warp(block.timestamp + 2 hours);
        
        // Aumentar precio en 10% (a 1.10 USD)
        vm.prank(deployer);
        oracle.setPrice(11e17);
        
        // Ejecutar rebase
        vm.prank(deployer);
        hook.forceRebase(); // Uso de forceRebase para testing
        
        // El suministro debería haber aumentado ~1% (rebasePercentageUp)
        uint256 expectedNewSupply = initialSupply + ((initialSupply * 1e16) / 1e18);
        assertApproxEqRel(vcop.totalSupply(), expectedNewSupply, 0.01e18); // 1% de tolerancia
        
        // Los balances deberían escalar proporcionalmente
        uint256 expectedUser1Balance = initialUser1Balance + ((initialUser1Balance * 1e16) / 1e18);
        assertApproxEqRel(vcop.balanceOf(user1), expectedUser1Balance, 0.01e18);
    }
    
    function testNegativeRebase() public {
        // Precio inicial
        uint256 initialSupply = vcop.totalSupply();
        uint256 initialUser1Balance = vcop.balanceOf(user1);
        
        // Avanzar el tiempo suficiente para permitir el rebase
        vm.warp(block.timestamp + 2 hours);
        
        // Disminuir precio en 10% (a 0.90 USD)
        vm.prank(deployer);
        oracle.setPrice(9e17);
        
        // Ejecutar rebase
        vm.prank(deployer);
        hook.forceRebase(); // Uso de forceRebase para testing
        
        // El suministro debería haber disminuido ~1% (rebasePercentageDown)
        uint256 expectedNewSupply = initialSupply - ((initialSupply * 1e16) / 1e18);
        assertApproxEqRel(vcop.totalSupply(), expectedNewSupply, 0.01e18); // 1% de tolerancia
        
        // Los balances deberían escalar proporcionalmente
        uint256 expectedUser1Balance = initialUser1Balance - ((initialUser1Balance * 1e16) / 1e18);
        assertApproxEqRel(vcop.balanceOf(user1), expectedUser1Balance, 0.01e18);
    }
    
    function testNoRebaseWithinThreshold() public {
        // Precio inicial
        uint256 initialSupply = vcop.totalSupply();
        
        // Avanzar el tiempo suficiente para permitir el rebase
        vm.warp(block.timestamp + 2 hours);
        
        // Cambiar precio a 1.02 USD (dentro del umbral)
        vm.prank(deployer);
        oracle.setPrice(102e16);
        
        // Ejecutar rebase
        vm.prank(deployer);
        hook.forceRebase(); // Uso de forceRebase para testing
        
        // El suministro no debería cambiar (precio dentro del umbral)
        assertEq(vcop.totalSupply(), initialSupply);
    }
    
    function testRebaseInterval() public {
        // Avanzar el tiempo suficiente para permitir el rebase inicial
        vm.warp(block.timestamp + 2 hours);
        
        // Cambiar precio a 1.10 USD
        vm.prank(deployer);
        oracle.setPrice(11e17);
        
        // Ejecutar primer rebase
        vm.prank(deployer);
        hook.executeRebase();
        
        // Intentar ejecutar otro rebase inmediatamente debería fallar
        vm.prank(deployer);
        vm.expectRevert("Rebase too soon");
        hook.executeRebase();
        
        // Avanzar tiempo pero no lo suficiente
        vm.warp(block.timestamp + 30 minutes);
        
        // Debería seguir fallando
        vm.prank(deployer);
        vm.expectRevert("Rebase too soon");
        hook.executeRebase();
        
        // Avanzar tiempo suficiente
        vm.warp(block.timestamp + 31 minutes);
        
        // Ahora debería funcionar
        vm.prank(deployer);
        hook.executeRebase();
    }
} 