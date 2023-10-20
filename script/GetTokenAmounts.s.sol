// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract TokenAmounts {

    function run() view external{

        address addr = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);  // specify the address

        uint256 bal = addr.balance;  // get the balance of Ether (in wei)

        console.log('ether balance: %s', bal);  // log the balance to the console
        address token0 = address(0x4ed7c70F96B99c776995fB64377f0d4aB3B0e1C1);//mUSDC deployed locally
        address token1 = address(0x59b670e9fA9D0A427751Af201D676719a970857b);//mUNI deployed locally


        uint256 balanceUNI = IERC20(token1).balanceOf(address(addr));
        console.log('mUNI balance: %s');  // log the balance to the console
        console.logUint(uint(balanceUNI));

        uint256 balanceUSDC = IERC20(token0).balanceOf(address(addr));
        console.log('mUSDC balance: %s');  // log the balance to the console
        console.logUint(uint(balanceUSDC));

    }
}
