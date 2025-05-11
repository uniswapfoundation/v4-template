#!/bin/bash
export RPC_URL=https://sepolia.base.org
forge script script/TestVCOPSystem.s.sol:TestVCOPSystem --via-ir --broadcast --fork-url $RPC_URL -vvvv
