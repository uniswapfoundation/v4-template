#!/bin/bash

# Direcciones y parámetros para el pool VCOP-USDC
export POOL_MANAGER_ADDRESS=0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408
export CURRENCY0_ADDRESS=0x036CbD53842c5426634e7929541eC2318f3dCF7e
export CURRENCY1_ADDRESS=0x9654e816C592b9794a6c20F97019C952BD69E1B0
export FEE=3000
export TICK_SPACING=60
export HOOK_ADDRESS=0x4eB4B9f731ECCaB556f3516550dd4A68fc3b0040

# Ejecutar el script de Forge
forge script script/ReadPoolState.sol:ReadPoolState --rpc-url https://sepolia.base.org -vvv 