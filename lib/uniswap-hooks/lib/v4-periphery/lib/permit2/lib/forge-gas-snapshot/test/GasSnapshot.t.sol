// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";
import {GasSnapshot} from "../src/GasSnapshot.sol";
import {SimpleOperations} from "../src/test/SimpleOperations.sol";
import {SimpleOperationsGas} from "../src/test/SimpleOperationsGas.sol";

contract GasSnapshotTest is Test {
    SimpleOperations simpleOperations;
    SimpleOperationsGas simpleOperationsGas;

    function setUp() public {
        simpleOperationsGas = new SimpleOperationsGas("");
    }

    function testAdd() public {
        simpleOperationsGas.testAddGas();

        string memory value = vm.readLine(".forge-snapshots/add.snap");
        assertEq(value, "134");
    }

    function testAddTwice() public {
        simpleOperationsGas.testAddGasTwice();

        string memory first = vm.readLine(".forge-snapshots/addFirst.snap");
        string memory second = vm.readLine(".forge-snapshots/addSecond.snap");

        assertEq(first, second);
        assertEq(first, "134");
    }

    function testManyAdd() public {
        simpleOperationsGas.testManyAddGas();

        string memory value = vm.readLine(".forge-snapshots/manyAdd.snap");
        assertEq(value, "19195");
    }

    function testManySstore() public {
        simpleOperationsGas.testManySstoreGas();

        string memory value = vm.readLine(".forge-snapshots/manySstore.snap");
        assertEq(value, "50990");
    }

    function testCheckManyAdd() public {
        vm.setEnv("FORGE_SNAPSHOT_CHECK", "true");
        SimpleOperationsGas otherGasTests = new SimpleOperationsGas("snap");
        // preloaded with the right value
        otherGasTests.testManyAddGas();
    }

    function testCheckManySstoreFails() public {
        vm.setEnv("FORGE_SNAPSHOT_CHECK", "true");
        SimpleOperationsGas otherGasTests = new SimpleOperationsGas("snap");
        // preloaded with the wrong value
        vm.expectRevert(
            abi.encodeWithSelector(GasSnapshot.GasMismatch.selector, 1, 50990)
        );
        otherGasTests.testManySstoreGas();
    }
}
