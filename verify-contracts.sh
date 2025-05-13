#!/bin/bash

# Script de verificación de contratos en BaseScan Sepolia
# Obtener variables de entorno o usar las proporcionadas
ETHERSCAN_API_KEY="${ETHERSCAN_API_KEY:-IS3DBRSG4KAU2T8BS54ECSD2TKSIT9T9CI}"

# Cargar direcciones de contratos desde cache/broadcast
LATEST_RUN=$(ls -t broadcast/DeployVCOPCollateral.sol/84532/run-*.json 2>/dev/null | head -1)
echo "Usando el último despliegue: $LATEST_RUN"

# Extraer direcciones de contratos desde variables de entorno si existen
if [ -f .env ]; then
    source .env
fi

# Direcciones del último despliegue (actualizadas)
MOCK_USDC_ADDRESS="0x57F652906F7a7594Aef967A11882d92B625029BE"
VCOP_COLLATERAL_ADDRESS="0x186f1e333e152Da6F941197ab8CE0A5F9bCd4034"
ORACLE_ADDRESS="0x65eB2a3AB4EccBa519E2ceCd397D29b5C96a2660"
COLLATERAL_HOOK_ADDRESS="0x2eCFce85d0128Fe3c5291dAb70616021796c04c0"
COLLATERAL_MANAGER_ADDRESS="0x461dd5d7D9c69E98bFc32fb44F03d6D478891419"
PRICE_CALCULATOR_ADDRESS="0xdcbE584756590D0Bf72d127832FEE3A7a77a87F4"
# Dirección del PoolManager en Base Sepolia
POOL_MANAGER_ADDRESS="0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408"

# Sobrescribir con valores de entorno si existen
MOCK_USDC_ADDRESS="${USDC_ADDRESS_ENV:-$MOCK_USDC_ADDRESS}"
VCOP_COLLATERAL_ADDRESS="${VCOP_COLLATERAL_ADDRESS_ENV:-$VCOP_COLLATERAL_ADDRESS}"
ORACLE_ADDRESS="${ORACLE_ADDRESS_ENV:-$ORACLE_ADDRESS}"
COLLATERAL_HOOK_ADDRESS="${HOOK_ADDRESS_ENV:-$COLLATERAL_HOOK_ADDRESS}"
COLLATERAL_MANAGER_ADDRESS="${COLLATERAL_MANAGER_ADDRESS_ENV:-$COLLATERAL_MANAGER_ADDRESS}"
PRICE_CALCULATOR_ADDRESS="${PRICE_CALCULATOR_ADDRESS_ENV:-$PRICE_CALCULATOR_ADDRESS}"

echo "Verificando contratos en BaseScan Sepolia..."
echo "USDC Simulado: $MOCK_USDC_ADDRESS"
echo "VCOP Colateralizado: $VCOP_COLLATERAL_ADDRESS"
echo "VCOP Oracle: $ORACLE_ADDRESS"
echo "VCOP Collateral Hook: $COLLATERAL_HOOK_ADDRESS"
echo "Collateral Manager: $COLLATERAL_MANAGER_ADDRESS"
echo "VCOP Price Calculator: $PRICE_CALCULATOR_ADDRESS"

# Verificar USDC Simulado (MockERC20)
echo "Verificando USDC Simulado (MockERC20)..."
forge verify-contract --chain-id 84532 \
    --compiler-version 0.8.26 \
    --watch \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $MOCK_USDC_ADDRESS src/mocks/MockERC20.sol:MockERC20 \
    --constructor-args $(cast abi-encode "constructor(string,string,uint8)" "USD Coin" "USDC" 6)

# Verificar VCOP Colateralizado
echo "Verificando VCOP Colateralizado..."
forge verify-contract --chain-id 84532 \
    --compiler-version 0.8.26 \
    --watch \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $VCOP_COLLATERAL_ADDRESS src/VcopCollateral/VCOPCollateralized.sol:VCOPCollateralized \
    --constructor-args $(cast abi-encode "constructor(uint256)" 1000000000000000)

# Verificar VCOP Oracle
echo "Verificando VCOP Oracle..."
forge verify-contract --chain-id 84532 \
    --compiler-version 0.8.26 \
    --watch \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $ORACLE_ADDRESS src/VcopCollateral/VCOPOracle.sol:VCOPOracle \
    --constructor-args $(cast abi-encode "constructor(uint256,address,address,address,uint24,int24,address)" 4200000000 $POOL_MANAGER_ADDRESS $VCOP_COLLATERAL_ADDRESS $MOCK_USDC_ADDRESS 3000 60 0x0000000000000000000000000000000000000000)

# Verificar VCOP Collateral Hook
echo "Verificando VCOP Collateral Hook..."
forge verify-contract --chain-id 84532 \
    --compiler-version 0.8.26 \
    --watch \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $COLLATERAL_HOOK_ADDRESS src/VcopCollateral/VCOPCollateralHook.sol:VCOPCollateralHook \
    --constructor-args $(cast abi-encode "constructor(address,address,address,address,address)" \
        $POOL_MANAGER_ADDRESS \
        $VCOP_COLLATERAL_ADDRESS \
        $ORACLE_ADDRESS \
        $VCOP_COLLATERAL_ADDRESS \
        $MOCK_USDC_ADDRESS)

# Verificar Collateral Manager
echo "Verificando Collateral Manager..."
forge verify-contract --chain-id 84532 \
    --compiler-version 0.8.26 \
    --watch \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $COLLATERAL_MANAGER_ADDRESS src/VcopCollateral/VCOPCollateralManager.sol:VCOPCollateralManager \
    --constructor-args $(cast abi-encode "constructor(address,address,address)" \
        $VCOP_COLLATERAL_ADDRESS \
        $COLLATERAL_HOOK_ADDRESS \
        $MOCK_USDC_ADDRESS)

# Verificar VCOP Price Calculator
echo "Verificando VCOP Price Calculator..."
forge verify-contract --chain-id 84532 \
    --compiler-version 0.8.26 \
    --watch \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $PRICE_CALCULATOR_ADDRESS src/VcopCollateral/VCOPPriceCalculator.sol:VCOPPriceCalculator \
    --constructor-args $(cast abi-encode "constructor(address,address,address,uint24,int24,address,uint256)" \
        $POOL_MANAGER_ADDRESS \
        $VCOP_COLLATERAL_ADDRESS \
        $MOCK_USDC_ADDRESS \
        3000 \
        60 \
        $COLLATERAL_HOOK_ADDRESS \
        4200000000)

echo "¡Verificación completada!" 