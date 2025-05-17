#!/bin/bash

# Script para interactuar con la implementación VCOP en Base mainnet
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

show_help() {
    echo -e "${BLUE}============= VCOP Mainnet Commands =============${NC}"
    echo -e "Este script facilita la interacción con el sistema VCOP desplegado en Base mainnet"
    echo
    echo -e "${GREEN}Opciones disponibles:${NC}"
    echo "  1) Verificar estado del PSM"
    echo "  2) Verificar precios"
    echo "  3) Swap VCOP a USDC"
    echo "  4) Swap USDC a VCOP"
    echo "  5) Verificar tasas del oracle"
    echo "  6) Verificar contratos en BaseScan"
    echo "  q) Salir"
    echo
}

run_command() {
    case $1 in
        1)
            echo -e "${BLUE}Verificando estado del PSM...${NC}"
            make check-psm-mainnet
            ;;
        2)
            echo -e "${BLUE}Verificando precios actuales...${NC}"
            make check-prices-mainnet
            ;;
        3)
            echo -e "${BLUE}Swap VCOP a USDC${NC}"
            read -p "Cantidad de VCOP (en formato con 6 decimales, ej: 100000000 para 100 VCOP): " amount
            if [[ -n $amount && $amount =~ ^[0-9]+$ ]]; then
                make swap-vcop-to-usdc-mainnet AMOUNT=$amount
            else
                echo -e "${RED}Cantidad inválida. Debe ser un número entero.${NC}"
            fi
            ;;
        4)
            echo -e "${BLUE}Swap USDC a VCOP${NC}"
            read -p "Cantidad de USDC (en formato con 6 decimales, ej: 10000000 para 10 USDC): " amount
            if [[ -n $amount && $amount =~ ^[0-9]+$ ]]; then
                make swap-usdc-to-vcop-mainnet AMOUNT=$amount
            else
                echo -e "${RED}Cantidad inválida. Debe ser un número entero.${NC}"
            fi
            ;;
        5)
            echo -e "${BLUE}Verificando tasas del oracle...${NC}"
            make check-new-oracle-mainnet
            ;;
        6)
            echo -e "${BLUE}Verificando contratos en BaseScan...${NC}"
            ./verify-contracts.sh
            ;;
        q|Q)
            exit 0
            ;;
        *)
            echo -e "${RED}Opción inválida${NC}"
            ;;
    esac
}

# Main loop
while true; do
    show_help
    read -p "Seleccione una opción: " option
    echo
    run_command $option
    echo
    read -p "Presione Enter para continuar..."
    clear
done 