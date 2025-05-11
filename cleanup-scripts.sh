#!/bin/bash

# Script para limpiar y reorganizar los scripts de Foundry
echo "Limpiando scripts antiguos o redundantes..."

# Crear directorio de archivos si no existe
mkdir -p script/archive

# Lista de scripts a archivar (versiones anteriores o redundantes)
SCRIPTS_TO_ARCHIVE=(
  "AddLiquidity.s.sol"
  "CreatePoolAndAddLiquidity.s.sol"
  "CreatePoolOnly.s.sol"
  "DeployVCOPWithPool.s.sol"
  "SimpleAddLiquidity.s.sol"
  "SimplePoolCreator.s.sol"
  "DeployVCOP.s.sol"
  "01_CreatePoolAndMintLiquidity.s.sol"
  "01a_CreatePoolOnly.s.sol"
  "02_AddLiquidity.s.sol"
  "03_Swap.s.sol"
  "00_Counter.s.sol"
)

# Mover scripts a la carpeta de archivos
for script in "${SCRIPTS_TO_ARCHIVE[@]}"; do
  if [ -f "script/$script" ]; then
    echo "Archivando $script..."
    mv "script/$script" "script/archive/"
  fi
done

# Ejecutar forge clean para eliminar artefactos de compilación
echo "Ejecutando forge clean..."
forge clean

echo "Limpieza completada. Los scripts antiguos se han movido a script/archive/"
echo "Scripts activos:"
ls -la script/*.sol

echo "Scripts archivados:"
ls -la script/archive/*.sol 