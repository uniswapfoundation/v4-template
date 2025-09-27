// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "src/base/BaseAsyncSwap.sol";

contract BaseAsyncSwapMock is BaseAsyncSwap {
    constructor(IPoolManager _poolManager) BaseAsyncSwap(_poolManager) {}

    // Exclude from coverage report
    function test() public {}
}
