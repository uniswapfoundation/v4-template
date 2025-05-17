#!/bin/bash

# Script para verificación de contratos en Base Mainnet
ETHERSCAN_API_KEY="${ETHERSCAN_API_KEY:-IS3DBRSG4KAU2T8BS54ECSD2TKSIT9T9CI}"

# Direcciones de los contratos desplegados en Base Mainnet
MOCK_USDC_ADDRESS="0xC9D7A317B5A9B39d971fA4430d0Fec7A572d2520"
VCOP_COLLATERAL_ADDRESS="0xE126098b5111330ceD47b80928348E4B8ED7A784"
ORACLE_ADDRESS="0xA3aCc71fDA8C0E321ea9d49eF0630Dc1c1951E17"
COLLATERAL_HOOK_ADDRESS="0x00feAFe88e9441C10227Be8CcF2DC34D691b84c0"
COLLATERAL_MANAGER_ADDRESS="0x5d211f80A23f04201C6b3Fa06B85171b11802B95"
PRICE_CALCULATOR_ADDRESS="0x5F56a7Eb5CD6aa8fC904d6dFEA676BE7C9Dabd26"
POOL_MANAGER_ADDRESS="0x498581ff718922c3f8e6a244956af099b2652b2b"
TREASURY_ADDRESS="0xA6B3D200cD34ca14d7579DAc8B054bf50a62c37c"

echo "Verificando contratos en Base Mainnet..."
echo "USDC Simulado: $MOCK_USDC_ADDRESS"
echo "VCOP Colateralizado: $VCOP_COLLATERAL_ADDRESS"
echo "VCOP Oracle: $ORACLE_ADDRESS"
echo "VCOP Collateral Hook: $COLLATERAL_HOOK_ADDRESS"
echo "Collateral Manager: $COLLATERAL_MANAGER_ADDRESS"
echo "VCOP Price Calculator: $PRICE_CALCULATOR_ADDRESS"

# Usar etherscan-verify directamente para cada contrato

# 1. Verificar USDC Simulado
echo -e "\nVerificando USDC Simulado (MockERC20)..."
forge verify-contract \
    --chain-id 8453 \
    --compiler-version 0.8.26 \
    --constructor-args $(cast abi-encode "constructor(string,string,uint8)" "USD Coin" "USDC" 6) \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $MOCK_USDC_ADDRESS \
    src/mocks/MockERC20.sol:MockERC20

# 2. Verificar VCOP Colateralizado
echo -e "\nVerificando VCOP Colateralizado..."
forge verify-contract \
    --chain-id 8453 \
    --compiler-version 0.8.26 \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $VCOP_COLLATERAL_ADDRESS \
    src/VcopCollateral/VCOPCollateralized.sol:VCOPCollateralized

# 3. Verificar VCOP Oracle
echo -e "\nVerificando VCOP Oracle..."
forge verify-contract \
    --chain-id 8453 \
    --compiler-version 0.8.26 \
    --constructor-args $(cast abi-encode "constructor(uint256,address,address,address,uint24,int24,address)" 4200000000 $POOL_MANAGER_ADDRESS $VCOP_COLLATERAL_ADDRESS $MOCK_USDC_ADDRESS 3000 60 0x0000000000000000000000000000000000000000) \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $ORACLE_ADDRESS \
    src/VcopCollateral/VCOPOracle.sol:VCOPOracle

# 4. Verificar VCOP Collateral Hook
echo -e "\nVerificando VCOP Collateral Hook..."
forge verify-contract \
    --chain-id 8453 \
    --compiler-version 0.8.26 \
    --constructor-args $(cast abi-encode "constructor(address,address,address,address,address,address,address)" $POOL_MANAGER_ADDRESS $COLLATERAL_MANAGER_ADDRESS $ORACLE_ADDRESS $VCOP_COLLATERAL_ADDRESS $MOCK_USDC_ADDRESS $TREASURY_ADDRESS $TREASURY_ADDRESS) \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $COLLATERAL_HOOK_ADDRESS \
    src/VcopCollateral/VCOPCollateralHook.sol:VCOPCollateralHook

# 5. Verificar Collateral Manager
echo -e "\nVerificando Collateral Manager..."
forge verify-contract \
    --chain-id 8453 \
    --compiler-version 0.8.26 \
    --constructor-args $(cast abi-encode "constructor(address,address)" $VCOP_COLLATERAL_ADDRESS $ORACLE_ADDRESS) \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $COLLATERAL_MANAGER_ADDRESS \
    src/VcopCollateral/VCOPCollateralManager.sol:VCOPCollateralManager

# 6. Verificar VCOP Price Calculator
echo -e "\nVerificando VCOP Price Calculator..."
forge verify-contract \
    --chain-id 8453 \
    --compiler-version 0.8.26 \
    --constructor-args $(cast abi-encode "constructor(address,address,address,uint24,int24,address,uint256)" $POOL_MANAGER_ADDRESS $VCOP_COLLATERAL_ADDRESS $MOCK_USDC_ADDRESS 3000 60 $COLLATERAL_HOOK_ADDRESS 4200000000) \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $PRICE_CALCULATOR_ADDRESS \
    src/VcopCollateral/VCOPPriceCalculator.sol:VCOPPriceCalculator

echo -e "\n¡Verificación completada!" 