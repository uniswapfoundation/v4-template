#!/bin/bash

# Direcciones y parámetros para el pool VCOP-USDC
export POOL_MANAGER_ADDRESS=0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408
export CURRENCY0_ADDRESS=0x036CbD53842c5426634e7929541eC2318f3dCF7e
export CURRENCY1_ADDRESS=0x9654e816C592b9794a6c20F97019C952BD69E1B0
export FEE=3000
export TICK_SPACING=60
export HOOK_ADDRESS=0x4eB4B9f731ECCaB556f3516550dd4A68fc3b0040

# Parámetros para el cálculo de cantidades de tokens
# Descomenta estas líneas si quieres especificar manualmente los rangos de ticks
# Nota: vm.envUint no puede manejar números negativos, así que los omitimos
# y usamos el cálculo automático en el script
# export TICK_LOWER_SET=true
# export TICK_LOWER=600
# export TICK_UPPER_SET=true
# export TICK_UPPER=600

# Parámetros opcionales para mostrar información de una posición específica
# Descomenta estas líneas y proporciona valores reales para ver la información de una posición
# export SHOW_POSITION=true
# export POSITION_OWNER="0xTuDireccion"
# export POSITION_TICK_LOWER=-60
# export POSITION_TICK_UPPER=60
# export POSITION_SALT="0x0000000000000000000000000000000000000000000000000000000000000000"

# Ejecutar el script de Forge con --via-ir para resolver el error "stack too deep"
forge script script/ReadPoolState.s.sol:ReadPoolState --rpc-url https://sepolia.base.org --via-ir -vvv 