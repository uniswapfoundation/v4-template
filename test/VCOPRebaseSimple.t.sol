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
    
    // Constantes - ahora con 6 decimales
    uint256 public initialVCOPSupply = 1_000_000 * 1e6;
    uint256 public initialUserBalance = 10_000 * 1e6;
    
    function setUp() public {
        // Cambiar a deployer
        vm.startPrank(deployer);
        
        // Desplegar VCOP token
        vcop = new VCOPRebased(initialVCOPSupply);
        
        // Desplegar Oracle con tasa inicial de 1:1 (1e6 = 1 COP)
        oracle = new VCOPOracle(1e6);
        
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
        assertEq(oracle.getVcopToCopRate(), 1e6);
    }
    
    function testPositiveRebase() public {
        // Precio inicial
        uint256 initialSupply = vcop.totalSupply();
        uint256 initialUser1Balance = vcop.balanceOf(user1);
        
        // Aumentar la tasa a 1.10 COP por VCOP (10% por encima del ideal)
        vm.prank(deployer);
        oracle.setVcopToCopRate(11e5);
        
        // Asegurar que deployer tiene permisos antes del rebase
        vm.startPrank(deployer);
        vcop.setRebaser(deployer, true);
        
        // Ejecutar rebase directamente como deployer
        vcop.rebase(oracle.getVcopToCopRate());
        vm.stopPrank();
        
        // El suministro debería haber aumentado ~1% (rebasePercentageUp)
        uint256 expectedNewSupply = initialSupply + ((initialSupply * 1e4) / 1e6);
        assertApproxEqRel(vcop.totalSupply(), expectedNewSupply, 0.01e18); // 1% de tolerancia
        
        // Los balances deberían escalar proporcionalmente
        uint256 expectedUser1Balance = initialUser1Balance + ((initialUser1Balance * 1e4) / 1e6);
        assertApproxEqRel(vcop.balanceOf(user1), expectedUser1Balance, 0.01e18);
    }
    
    function testNegativeRebase() public {
        // Precio inicial
        uint256 initialSupply = vcop.totalSupply();
        uint256 initialUser1Balance = vcop.balanceOf(user1);
        
        // Disminuir la tasa a 0.90 COP por VCOP (10% por debajo del ideal)
        vm.prank(deployer);
        oracle.setVcopToCopRate(9e5);
        
        // Asegurar que deployer tiene permisos antes del rebase
        vm.startPrank(deployer);
        vcop.setRebaser(deployer, true);
        
        // Ejecutar rebase
        vcop.rebase(oracle.getVcopToCopRate());
        vm.stopPrank();
        
        // El suministro debería haber disminuido ~1% (rebasePercentageDown)
        uint256 expectedNewSupply = initialSupply - ((initialSupply * 1e4) / 1e6);
        assertApproxEqRel(vcop.totalSupply(), expectedNewSupply, 0.01e18); // 1% de tolerancia
        
        // Los balances deberían escalar proporcionalmente
        uint256 expectedUser1Balance = initialUser1Balance - ((initialUser1Balance * 1e4) / 1e6);
        assertApproxEqRel(vcop.balanceOf(user1), expectedUser1Balance, 0.01e18);
    }
    
    function testNoRebaseWithinThreshold() public {
        // Precio inicial
        uint256 initialSupply = vcop.totalSupply();
        
        // Cambiar tasa a 1.02 COP por VCOP (dentro del umbral)
        vm.prank(deployer);
        oracle.setVcopToCopRate(102e4);
        
        // Asegurar que deployer tiene permisos antes del rebase
        vm.startPrank(deployer);
        vcop.setRebaser(deployer, true);
        
        // Ejecutar rebase
        vcop.rebase(oracle.getVcopToCopRate());
        vm.stopPrank();
        
        // El suministro no debería cambiar (tasa dentro del umbral)
        assertEq(vcop.totalSupply(), initialSupply);
    }
} 