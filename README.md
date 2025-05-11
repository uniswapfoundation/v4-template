# VCOP Stablecoin con Uniswap v4

Una stablecoin algorítmica basada en mecanismo de rebase y pools de Uniswap v4.

## Descripción

VCOP es una stablecoin que utiliza un mecanismo de rebase para mantener su precio objetivo de 1 USD. El sistema integra:

- Token VCOP con mecanismo de rebase
- Oráculo de precio
- Hook de Uniswap v4 para automatizar rebases
- Pool de liquidez en Uniswap v4

## Requisitos

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js y npm
- ETH en Base Sepolia para pagar gas
- USDC en Base Sepolia para añadir liquidez

## Instalación

```bash
# Clonar el repositorio
git clone <repositorio>
cd vcop_test

# Instalar dependencias
forge install
```

## Flujo de Despliegue

El despliegue puede realizarse en un entorno local o en la red Base Sepolia.

### Opción 1: Despliegue en Base Sepolia

#### 1. Configuración del archivo .env

El archivo `.env` ya está configurado con las direcciones oficiales de los contratos de Uniswap v4 en Base Sepolia. Solo necesitas actualizar tu clave privada:

```
# Reemplaza con tu clave privada real (debe incluir el prefijo 0x)
PRIVATE_KEY=0xtu_clave_privada_aqui

# Base Sepolia RPC URL
RPC_URL=https://sepolia.base.org

# Direcciones oficiales de Uniswap v4 en Base Sepolia (ChainID: 84532)
POOL_MANAGER_ADDRESS=0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408
POSITION_MANAGER_ADDRESS=0x4b2c77d209d3405f41a037ec6c77f7f5b8e2ca80

# USDC en Base Sepolia
USDC_ADDRESS=0x036CbD53842c5426634e7929541eC2318f3dCF7e
```

#### 2. Obtener USDC en Base Sepolia

Antes de desplegar, asegúrate de tener suficiente USDC en Base Sepolia para añadir liquidez inicial. El script está configurado para utilizar 50 USDC.

#### 3. Desplegar el Sistema VCOP Completo

Ejecuta el script de despliegue completo:

```bash
# Usar la opción --via-ir para resolver posibles errores "stack too deep"
forge script script/DeployVCOPComplete.s.sol:DeployVCOPComplete --via-ir --broadcast --rpc-url base-sepolia
```

Este script realiza el proceso de despliegue en tres pasos:

1. **Paso 1**: Despliega el token VCOP y el Oráculo
2. **Paso 2**: Usa HookMiner para encontrar y desplegar el hook con una dirección válida para Uniswap v4
3. **Paso 3**: Crea el pool VCOP/USDC y añade liquidez inicial

Los contratos desplegados y sus direcciones se mostrarán en la salida del script.

#### 4. Verificar Contratos en BaseScan Sepolia

Puedes verificar automáticamente los contratos desplegados usando el script incluido:

```bash
./verify-contracts.sh
```

El script verifica:
- VCOP Token
- VCOP Oracle
- VCOP Rebase Hook

### Opción 2: Entorno Local con Anvil

Para pruebas locales, puedes seguir utilizando Anvil:

#### 1. Iniciar nodo local

```bash
anvil
```

#### 2. Desplegar Contratos Base de Uniswap v4

```bash
forge script script/Anvil.s.sol --broadcast --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

#### 3. Ejecutar el despliegue completo

```bash
forge script script/DeployVCOPComplete.s.sol:DeployVCOPComplete --via-ir --broadcast --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

## Scripts Principales

| Script | Descripción |
|--------|-------------|
| `DeployVCOPComplete.s.sol` | Script principal para desplegar todo el sistema VCOP |
| `DeployVCOPRebaseHook.s.sol` | Script auxiliar para desplegar el hook de rebase |
| `MintVCOPToWallet.s.sol` | Minta tokens VCOP a una dirección específica |
| `ReadPoolState.sol` | Lee el estado del pool de Uniswap v4 |
| `ReadVCOPPoolState.s.sol` | Lee el estado específico del pool VCOP/USDC |
| `Anvil.s.sol` | Configura el entorno local de Anvil |

Los scripts antiguos y ejemplos se han movido a la carpeta `script/archive`.

## ¿Por qué necesitamos HookMiner?

En Uniswap v4, los hooks deben tener direcciones especiales que codifican los permisos que utilizan. HookMiner encuentra una "salt" para desplegar el contrato mediante CREATE2 en una dirección que tiene los bits correctos, lo que permite que Uniswap v4 valide qué hooks están habilitados.

## Contratos Principales

- `VCOPRebased.sol`: Token principal con mecanismo de rebase
- `VCOPOracle.sol`: Oráculo de precio (mock para fines de prueba)
- `VCOPRebaseHook.sol`: Hook de Uniswap v4 que ejecuta rebases automáticamente

## Pruebas

Para ejecutar las pruebas:

```bash
forge test -vv
```

## Interactuar con el Sistema

Una vez desplegado, puedes:

1. Modificar el precio en el oráculo para desencadenar rebases
2. Realizar swaps en el pool para probar el hook
3. Verificar cambios en el suministro total tras rebases

## Seguridad

Este código es experimental y no está auditado. No se recomienda su uso en producción. 