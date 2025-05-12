#!/bin/bash

# Script de verificación de contratos en BaseScan Sepolia
# Obtener variables de entorno o usar las proporcionadas
ETHERSCAN_API_KEY="${ETHERSCAN_API_KEY:-IS3DBRSG4KAU2T8BS54ECSD2TKSIT9T9CI}"

# Cargar direcciones de contratos desde cache/broadcast
LATEST_RUN=$(ls -t broadcast/SimpleDeploy.sol/84532/run-*.json | head -1)
echo "Usando el último despliegue: $LATEST_RUN"

# Extraer direcciones de contratos desde variables de entorno si existen
if [ -f .env ]; then
    source .env
fi

# Direcciones del último despliegue (actualizadas)
VCOP_ADDRESS="0x23d4741bFcd9F7560ac37ACeECddfCdC35A1994f"
ORACLE_ADDRESS="0xaCfe7a7b680110F4F5c7F289f8F2C0fb9a30D22d"
HOOK_ADDRESS="0x90C2ab6887ae73f481E442b2B2Da1F0C54760040"
MOCK_USDC_ADDRESS="0xC30ae597EA9d1C917D227C563C3a62E238D2fD40"
PRICE_CALCULATOR_ADDRESS="0x340C20A4625DF3C7B3Bc5857b4f841C524Ff8b9D"
# Dirección del PoolManager en Base Sepolia
POOL_MANAGER_ADDRESS="0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408"

# Sobrescribir con valores de entorno si existen
VCOP_ADDRESS="${VCOP_ADDRESS_ENV:-$VCOP_ADDRESS}"
ORACLE_ADDRESS="${ORACLE_ADDRESS_ENV:-$ORACLE_ADDRESS}"
HOOK_ADDRESS="${HOOK_ADDRESS_ENV:-$HOOK_ADDRESS}"
MOCK_USDC_ADDRESS="${USDC_ADDRESS_ENV:-$MOCK_USDC_ADDRESS}"
PRICE_CALCULATOR_ADDRESS="${PRICE_CALCULATOR_ADDRESS_ENV:-$PRICE_CALCULATOR_ADDRESS}"

echo "Verificando contratos en BaseScan Sepolia..."
echo "VCOP Token: $VCOP_ADDRESS"
echo "VCOP Oracle: $ORACLE_ADDRESS"
echo "VCOP Rebase Hook: $HOOK_ADDRESS"
echo "USDC Simulado: $MOCK_USDC_ADDRESS"
echo "VCOP Price Calculator: $PRICE_CALCULATOR_ADDRESS"

# Verificar VCOP Token
echo "Verificando VCOP Token..."
forge verify-contract --chain-id 84532 \
    --compiler-version 0.8.26 \
    --watch \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $VCOP_ADDRESS src/VCOPRebased.sol:VCOPRebased \
    --constructor-args $(cast abi-encode "constructor(uint256)" 1000000000000000)

# Verificar VCOP Oracle
echo "Verificando VCOP Oracle..."
forge verify-contract --chain-id 84532 \
    --compiler-version 0.8.26 \
    --watch \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $ORACLE_ADDRESS src/VCOPOracle.sol:VCOPOracle \
    --constructor-args $(cast abi-encode "constructor(uint256,address,address,address,uint24,int24,address)" 4200000000 $POOL_MANAGER_ADDRESS $VCOP_ADDRESS $MOCK_USDC_ADDRESS 3000 60 0x0000000000000000000000000000000000000000)

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

# Verificar VCOP Price Calculator
echo "Verificando VCOP Price Calculator..."
forge verify-contract --chain-id 84532 \
    --compiler-version 0.8.26 \
    --watch \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $PRICE_CALCULATOR_ADDRESS src/VCOPPriceCalculator.sol:VCOPPriceCalculator \
    --constructor-args $(cast abi-encode "constructor(address,address,address,uint24,int24,address,uint256)" \
        $POOL_MANAGER_ADDRESS \
        $VCOP_ADDRESS \
        $MOCK_USDC_ADDRESS \
        3000 \
        60 \
        $HOOK_ADDRESS \
        4200000000)

echo "¡Verificación completada!" 