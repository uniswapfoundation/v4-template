#!/bin/bash

# Script para leer el precio actual del pool VCOP-USDC en Base Sepolia
# Este script ejecuta TestPoolPrice.s.sol para obtener información detallada
# del precio actual de VCOP en relación a USDC y COP

echo "Leyendo precio actual del pool VCOP-USDC en Base Sepolia..."
echo ""

# RPC_URL puede ser tomado del .env o usar directamente Base Sepolia
RPC_URL=${RPC_URL:-https://sepolia.base.org}

# Ejecutar script con forge
forge script script/TestPoolPrice.s.sol --rpc-url $RPC_URL

echo ""
echo "Lectura completada." 