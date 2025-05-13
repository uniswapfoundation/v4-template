#!/bin/bash

# Script simplificado de verificación de contratos en BaseScan Sepolia
ETHERSCAN_API_KEY="${ETHERSCAN_API_KEY:-IS3DBRSG4KAU2T8BS54ECSD2TKSIT9T9CI}"

# Direcciones de los contratos desplegados
MOCK_USDC_ADDRESS="0xa255BDcDa0673Fe52e26dB4c5016434a7f54C2E8"
VCOP_COLLATERAL_ADDRESS="0x9Fcf266213854A7797A8a63183E180FeaD27fFc3"
ORACLE_ADDRESS="0x41a2c54F5510303b5eBDf43d47dC9a7812ea0886"
COLLATERAL_HOOK_ADDRESS="0x8e8bF46E3dF822aA10dE530C022037F4FC3144c0"
COLLATERAL_MANAGER_ADDRESS="0xD9d5515b96c3caabE88cEA72584e367A97a95b49"
PRICE_CALCULATOR_ADDRESS="0x09E23D6828a2e23B0C77C2c7Ba91182b5A28Ad47"
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
    /home/saritu/Documentos/VCOPstablecoinUniswapv4/src/mocks/MockERC20.sol:MockERC20

# 2. Verificar VCOP Colateralizado
echo -e "\nVerificando VCOP Colateralizado..."
forge verify-contract \
    --chain-id 84532 \
    --compiler-version 0.8.26 \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $VCOP_COLLATERAL_ADDRESS \
    /home/saritu/Documentos/VCOPstablecoinUniswapv4/src/VcopCollateral/VCOPCollateralized.sol:VCOPCollateralized

# 3. Verificar VCOP Oracle
echo -e "\nVerificando VCOP Oracle..."
forge verify-contract \
    --chain-id 84532 \
    --compiler-version 0.8.26 \
    --constructor-args $(cast abi-encode "constructor(uint256,address,address,address,uint24,int24,address)" 4200000000 $POOL_MANAGER_ADDRESS $VCOP_COLLATERAL_ADDRESS $MOCK_USDC_ADDRESS 3000 60 0x0000000000000000000000000000000000000000) \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $ORACLE_ADDRESS \
    /home/saritu/Documentos/VCOPstablecoinUniswapv4/src/VcopCollateral/VCOPOracle.sol:VCOPOracle

# 4. Verificar VCOP Collateral Hook
echo -e "\nVerificando VCOP Collateral Hook..."
forge verify-contract \
    --chain-id 84532 \
    --compiler-version 0.8.26 \
    --constructor-args $(cast abi-encode "constructor(address,address,address,address,address,address)" $POOL_MANAGER_ADDRESS $COLLATERAL_MANAGER_ADDRESS $ORACLE_ADDRESS $VCOP_COLLATERAL_ADDRESS $MOCK_USDC_ADDRESS $TREASURY_ADDRESS) \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $COLLATERAL_HOOK_ADDRESS \
    /home/saritu/Documentos/VCOPstablecoinUniswapv4/src/VcopCollateral/VCOPCollateralHook.sol:VCOPCollateralHook

# 5. Verificar Collateral Manager
echo -e "\nVerificando Collateral Manager..."
forge verify-contract \
    --chain-id 84532 \
    --compiler-version 0.8.26 \
    --constructor-args $(cast abi-encode "constructor(address,address)" $VCOP_COLLATERAL_ADDRESS $ORACLE_ADDRESS) \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $COLLATERAL_MANAGER_ADDRESS \
    /home/saritu/Documentos/VCOPstablecoinUniswapv4/src/VcopCollateral/VCOPCollateralManager.sol:VCOPCollateralManager

# 6. Verificar VCOP Price Calculator
echo -e "\nVerificando VCOP Price Calculator..."
forge verify-contract \
    --chain-id 84532 \
    --compiler-version 0.8.26 \
    --constructor-args $(cast abi-encode "constructor(address,address,address,uint24,int24,address,uint256)" $POOL_MANAGER_ADDRESS $VCOP_COLLATERAL_ADDRESS $MOCK_USDC_ADDRESS 3000 60 $COLLATERAL_HOOK_ADDRESS 4200000000) \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    $PRICE_CALCULATOR_ADDRESS \
    /home/saritu/Documentos/VCOPstablecoinUniswapv4/src/VcopCollateral/VCOPPriceCalculator.sol:VCOPPriceCalculator

echo -e "\n¡Verificación completada!" 