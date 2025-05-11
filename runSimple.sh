#!/bin/bash
export RPC_URL=https://sepolia.base.org

echo "======== Compilando contratos simplificados ========"
forge build script/SimpleDeploy.sol script/SimpleTest.sol

echo "======== Ejecutando despliegue simplificado ========"
forge script script/SimpleDeploy.sol:SimpleDeploy --via-ir --broadcast --fork-url $RPC_URL -vvv

echo "======== Ejecutando prueba simplificada ========"
forge script script/SimpleTest.sol:SimpleTest --via-ir --broadcast --fork-url $RPC_URL -vvv
