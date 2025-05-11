#!/bin/bash
export RPC_URL=https://sepolia.base.org
forge script script/DeployVCOPComplete.s.sol:DeployVCOPComplete --via-ir --broadcast --fork-url $RPC_URL -vvvv
