#!/bin/bash

# Script de verificación de contratos en BaseScan Sepolia
# Obtener variables de entorno o usar las proporcionadas
ETHERSCAN_API_KEY="${ETHERSCAN_API_KEY:-IS3DBRSG4KAU2T8BS54ECSD2TKSIT9T9CI}"

# Cargar direcciones de contratos desde cache/broadcast
LATEST_RUN=$(ls -t broadcast/DeployVCOPComplete.s.sol/84532/run-*.json | head -1)
echo "Usando el último despliegue: $LATEST_RUN"

# Extraer direcciones de contratos desde variables de entorno si existen
if [ -f .env ]; then
    source .env
fi

# Hardcodear las direcciones del último despliegue conocido
VCOP_ADDRESS="0x9654e816C592b9794a6c20F97019C952BD69E1B0"
ORACLE_ADDRESS="0x3c327daB3Ea56C213800d5CB79bdbc66Db7D3B91"
HOOK_ADDRESS="0x4eB4B9f731ECCaB556f3516550dd4A68fc3b0040"
USDC_ADDRESS="0x036CbD53842c5426634e7929541eC2318f3dCF7e"
# Dirección del PoolManager en Base Sepolia
POOL_MANAGER_ADDRESS="0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408"

# Sobrescribir con valores de entorno si existen
VCOP_ADDRESS="${VCOP_ADDRESS_ENV:-$VCOP_ADDRESS}"
ORACLE_ADDRESS="${ORACLE_ADDRESS_ENV:-$ORACLE_ADDRESS}"
HOOK_ADDRESS="${HOOK_ADDRESS_ENV:-$HOOK_ADDRESS}"

echo "Verificando contratos en BaseScan Sepolia..."
echo "VCOP Token: $VCOP_ADDRESS"
echo "VCOP Oracle: $ORACLE_ADDRESS"
echo "VCOP Rebase Hook: $HOOK_ADDRESS"

# Verificar VCOP Token
echo "Verificando VCOP Token..."
forge verify-contract --chain-id 84532 \
    --compiler-version 0.8.26 \
    --watch \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $VCOP_ADDRESS src/VCOPRebased.sol:VCOPRebased \
    --constructor-args $(cast abi-encode "constructor(uint256)" 1000000000000000000000000)

# Verificar VCOP Oracle
echo "Verificando VCOP Oracle..."
forge verify-contract --chain-id 84532 \
    --compiler-version 0.8.26 \
    --watch \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $ORACLE_ADDRESS src/VCOPOracle.sol:VCOPOracle \
    --constructor-args $(cast abi-encode "constructor(uint256)" 1000000000000000000)

# Verificar VCOP Rebase Hook
echo "Verificando VCOP Rebase Hook..."
forge verify-contract --chain-id 84532 \
    --compiler-version 0.8.26 \
    --watch \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $HOOK_ADDRESS src/VCOPRebaseHook.sol:VCOPRebaseHook \
    --constructor-args $(cast abi-encode "constructor(address,address,address,address,address)" \
        $POOL_MANAGER_ADDRESS \
        $VCOP_ADDRESS \
        $ORACLE_ADDRESS \
        $VCOP_ADDRESS \
        $USDC_ADDRESS)

echo "¡Verificación completada!" 