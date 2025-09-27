// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {GasSnapshot} from "../GasSnapshot.sol";
import {SimpleOperations} from "./SimpleOperations.sol";

contract SimpleOperationsGas is SimpleOperations, GasSnapshot {
    string internal prefix;

    constructor(string memory _prefix) {
        prefix = _prefix;
    }

    function testAddGas() external {
        snapStart(string(abi.encodePacked(prefix, "add")));
        add();
        snapEnd();
    }

    function testAddGasTwice() external {
        snapStart(string(abi.encodePacked(prefix, "addFirst")));
        add();
        snapEnd();

        snapStart(string(abi.encodePacked(prefix, "addSecond")));
        add();
        snapEnd();
    }

    function testManyAddGas() external {
        snapStart(string(abi.encodePacked(prefix, "manyAdd")));
        manyAdd();
        snapEnd();
    }

    function testManySstoreGas() external {
        snapStart(string(abi.encodePacked(prefix, "manySstore")));
        manySstore();
        snapEnd();
    }
}
