// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "src/fee/BaseDynamicFee.sol";

contract BaseDynamicFeeMock is BaseDynamicFee {
    uint24 public fee;

    constructor(IPoolManager _poolManager) BaseDynamicFee(_poolManager) {}

    function _getFee(PoolKey calldata) internal view override returns (uint24) {
        return fee;
    }

    function setFee(uint24 _fee) public {
        fee = _fee;
    }

    // Exclude from coverage report
    function test() public {}
}
