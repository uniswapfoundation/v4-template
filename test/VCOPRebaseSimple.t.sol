// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {VCOPRebased} from "../src/VCOPRebased.sol";
import {VCOPOracle} from "../src/VCOPOracle.sol";

// Test simplificado para VCOP Rebased sin dependencias de Uniswap
contract VCOPRebaseSimpleTest is Test {
    // Contratos
    VCOPRebased public vcop;
    VCOPOracle public oracle;
    
    // Direcciones
    address public deployer = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    
    // Constantes
    uint256 public initialVCOPSupply = 1_000_000 * 1e18;
    uint256 public initialUserBalance = 10_000 * 1e18;
    
    function setUp() public {
        // Cambiar a deployer
        vm.startPrank(deployer);
        
        // Desplegar VCOP token
        vcop = new VCOPRebased(initialVCOPSupply);
        
        // Desplegar Oracle
        oracle = new VCOPOracle(1e18); // Precio inicial: 1 USD
        
        // Autorizar a deployer para ejecutar rebases
        vcop.setRebaser(deployer, true);
        
        // Transferir algunos tokens a los usuarios para pruebas
        vcop.transfer(user1, initialUserBalance);
        vcop.transfer(user2, initialUserBalance);
        
        vm.stopPrank();
    }
    
    function testInitialState() public view {
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
        
        // Aumentar precio en 10% (a 1.10 USD)
        vm.prank(deployer);
        oracle.setPrice(11e17);
        
        // Ejecutar rebase directamente como deployer
        vm.prank(deployer);
        vcop.rebase(oracle.getPrice());
        
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
        
        // Disminuir precio en 10% (a 0.90 USD)
        vm.prank(deployer);
        oracle.setPrice(9e17);
        
        // Ejecutar rebase
        vm.prank(deployer);
        vcop.rebase(oracle.getPrice());
        
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
        
        // Cambiar precio a 1.02 USD (dentro del umbral)
        vm.prank(deployer);
        oracle.setPrice(102e16);
        
        // Ejecutar rebase
        vm.prank(deployer);
        vcop.rebase(oracle.getPrice());
        
        // El suministro no debería cambiar (precio dentro del umbral)
        assertEq(vcop.totalSupply(), initialSupply);
    }
} 