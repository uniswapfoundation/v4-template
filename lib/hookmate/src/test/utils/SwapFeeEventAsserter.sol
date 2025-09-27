// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { Vm } from "forge-std/Vm.sol";

/**
 * @title Swap Fee Event Asserter
 * @author saucepoint, akshatmittal
 */
library SwapFeeEventAsserter {
    function getSwapFeeFromEvent(Vm.Log[] memory recordedLogs) internal pure returns (uint24 fee) {
        for (uint256 i; i < recordedLogs.length; i++) {
            if (recordedLogs[i].topics[0] == IPoolManager.Swap.selector) {
                (,,,,, fee) = abi.decode(recordedLogs[i].data, (int128, int128, uint160, uint128, int24, uint24));
                break;
            }
        }
    }

    function assertSwapFee(Vm vm, Vm.Log[] memory recordedLogs, uint24 expectedFee) internal pure {
        vm.assertEq(getSwapFeeFromEvent(recordedLogs), expectedFee);
    }
}
