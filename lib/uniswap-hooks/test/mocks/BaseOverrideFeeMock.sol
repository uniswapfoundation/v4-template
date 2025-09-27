// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "src/fee/BaseOverrideFee.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";

contract BaseOverrideFeeMock is BaseOverrideFee {
    uint24 public fee;

    constructor(IPoolManager _poolManager) BaseOverrideFee(_poolManager) {}

    function _getFee(address, PoolKey calldata, SwapParams calldata, bytes calldata)
        internal
        view
        override
        returns (uint24)
    {
        return fee;
    }

    function setFee(uint24 _fee) public {
        fee = _fee;
    }

    // Exclude from coverage report
    function test() public {}
}
