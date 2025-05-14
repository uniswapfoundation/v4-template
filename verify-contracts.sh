#!/bin/bash

# Script simplificado de verificación de contratos en BaseScan Sepolia
ETHERSCAN_API_KEY="${ETHERSCAN_API_KEY:-IS3DBRSG4KAU2T8BS54ECSD2TKSIT9T9CI}"

# Direcciones de los contratos desplegados
MOCK_USDC_ADDRESS="0xF1A811E804b01A113fCE804f2b1C98bE25Ff8557"
VCOP_COLLATERAL_ADDRESS="0x7aa903a5fEe8F484575D5B8c43f5516504D29306"
ORACLE_ADDRESS="0xCE578C179b73b50Eba41b3121a11eB4AeE1EBA7a"
COLLATERAL_HOOK_ADDRESS="0xF62b7C4F66353C1ae2486595b3040f27fe4e44C0"
COLLATERAL_MANAGER_ADDRESS="0x8da23521353163Cb88451a49488c5A287a34EDD3"
PRICE_CALCULATOR_ADDRESS="0x2199b19B4E83E2942B766320b2e3a92e9CbA3846"
POOL_MANAGER_ADDRESS="0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408"
TREASURY_ADDRESS="0xA6B3D200cD34ca14d7579DAc8B054bf50a62c37c"

echo "Verificando contratos en BaseScan Sepolia..."
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
    --chain-id 84532 \
    --compiler-version 0.8.26 \
    --constructor-args $(cast abi-encode "constructor(string,string,uint8)" "USD Coin" "USDC" 6) \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $MOCK_USDC_ADDRESS \
    src/mocks/MockERC20.sol:MockERC20

# 2. Verificar VCOP Colateralizado
echo -e "\nVerificando VCOP Colateralizado..."
forge verify-contract \
    --chain-id 84532 \
    --compiler-version 0.8.26 \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $VCOP_COLLATERAL_ADDRESS \
    src/VcopCollateral/VCOPCollateralized.sol:VCOPCollateralized

# 3. Verificar VCOP Oracle
echo -e "\nVerificando VCOP Oracle..."
forge verify-contract \
    --chain-id 84532 \
    --compiler-version 0.8.26 \
    --constructor-args $(cast abi-encode "constructor(uint256,address,address,address,uint24,int24,address)" 4200000000 $POOL_MANAGER_ADDRESS $VCOP_COLLATERAL_ADDRESS $MOCK_USDC_ADDRESS 3000 60 0x0000000000000000000000000000000000000000) \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $ORACLE_ADDRESS \
    src/VcopCollateral/VCOPOracle.sol:VCOPOracle

# 4. Verificar VCOP Collateral Hook
echo -e "\nVerificando VCOP Collateral Hook..."
forge verify-contract \
    --chain-id 84532 \
    --compiler-version 0.8.26 \
    --constructor-args $(cast abi-encode "constructor(address,address,address,address,address,address,address)" $POOL_MANAGER_ADDRESS $COLLATERAL_MANAGER_ADDRESS $ORACLE_ADDRESS $VCOP_COLLATERAL_ADDRESS $MOCK_USDC_ADDRESS $TREASURY_ADDRESS $TREASURY_ADDRESS) \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $COLLATERAL_HOOK_ADDRESS \
    src/VcopCollateral/VCOPCollateralHook.sol:VCOPCollateralHook

# 5. Verificar Collateral Manager
echo -e "\nVerificando Collateral Manager..."
forge verify-contract \
    --chain-id 84532 \
    --compiler-version 0.8.26 \
    --constructor-args $(cast abi-encode "constructor(address,address)" $VCOP_COLLATERAL_ADDRESS $ORACLE_ADDRESS) \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $COLLATERAL_MANAGER_ADDRESS \
    src/VcopCollateral/VCOPCollateralManager.sol:VCOPCollateralManager

# 6. Verificar VCOP Price Calculator
echo -e "\nVerificando VCOP Price Calculator..."
forge verify-contract \
    --chain-id 84532 \
    --compiler-version 0.8.26 \
    --constructor-args $(cast abi-encode "constructor(address,address,address,uint24,int24,address,uint256)" $POOL_MANAGER_ADDRESS $VCOP_COLLATERAL_ADDRESS $MOCK_USDC_ADDRESS 3000 60 $COLLATERAL_HOOK_ADDRESS 4200000000) \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $PRICE_CALCULATOR_ADDRESS \
    src/VcopCollateral/VCOPPriceCalculator.sol:VCOPPriceCalculator

echo -e "\n¡Verificación completada!" 