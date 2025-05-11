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
VCOP_ADDRESS="0x5C624B7d9160655Aca8Ea4031F81E2a8aF851Add"
ORACLE_ADDRESS="0x3bb3BF4d9Ff26Ab3D1844d7ff13aA90206A00ef8"
HOOK_ADDRESS="0x11d96c8bfEcdBE06C683CC0935c12D6bf0DB0040"
MOCK_USDC_ADDRESS="0x356338EB7Ded4A356964806e23BCA4bBBeA3dC82"
# Dirección del PoolManager en Base Sepolia
POOL_MANAGER_ADDRESS="0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408"

# Sobrescribir con valores de entorno si existen
VCOP_ADDRESS="${VCOP_ADDRESS_ENV:-$VCOP_ADDRESS}"
ORACLE_ADDRESS="${ORACLE_ADDRESS_ENV:-$ORACLE_ADDRESS}"
HOOK_ADDRESS="${HOOK_ADDRESS_ENV:-$HOOK_ADDRESS}"
MOCK_USDC_ADDRESS="${USDC_ADDRESS_ENV:-$MOCK_USDC_ADDRESS}"

echo "Verificando contratos en BaseScan Sepolia..."
echo "VCOP Token: $VCOP_ADDRESS"
echo "VCOP Oracle: $ORACLE_ADDRESS"
echo "VCOP Rebase Hook: $HOOK_ADDRESS"
echo "USDC Simulado: $MOCK_USDC_ADDRESS"

# Verificar VCOP Token
echo "Verificando VCOP Token..."
forge verify-contract --chain-id 84532 \
    --compiler-version 0.8.26 \
    --watch \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $VCOP_ADDRESS src/VCOPRebased.sol:VCOPRebased \
    --constructor-args $(cast abi-encode "constructor(uint256)" 100000000000000000000000000)

# Verificar VCOP Oracle
echo "Verificando VCOP Oracle..."
forge verify-contract --chain-id 84532 \
    --compiler-version 0.8.26 \
    --watch \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $ORACLE_ADDRESS src/VCOPOracle.sol:VCOPOracle \
    --constructor-args $(cast abi-encode "constructor(uint256)" 4200000000000000000000)

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
        $MOCK_USDC_ADDRESS)

# Verificar USDC Simulado (MockERC20)
echo "Verificando USDC Simulado (MockERC20)..."
forge verify-contract --chain-id 84532 \
    --compiler-version 0.8.26 \
    --watch \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $MOCK_USDC_ADDRESS src/mocks/MockERC20.sol:MockERC20 \
    --constructor-args $(cast abi-encode "constructor(string,string,uint8)" "USD Coin" "USDC" 6)

echo "¡Verificación completada!" 