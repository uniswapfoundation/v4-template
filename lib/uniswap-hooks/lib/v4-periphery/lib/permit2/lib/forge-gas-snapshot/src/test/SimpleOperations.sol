// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

contract SimpleOperations {
    uint256 internal test;

    function add() public pure {
        uint256 x = 1;
        x++;
    }

    function manyAdd() public pure {
        uint256 x;
        for (uint256 i = 0; i < 100; i++) {
            x = i + 1;
        }
    }

    function manySstore() public {
        for (uint256 i = 0; i < 100; i++) {
            test = i + 2;
        }
    }
}
