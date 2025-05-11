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

## Configuración

1. Asegúrate de tener instalado Foundry:
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. Clona este repositorio:
```bash
git clone https://github.com/tu-usuario/VCOPstablecoinUniswapv4.git
cd VCOPstablecoinUniswapv4
```

3. Instala las dependencias:
```bash
forge install
```

4. Configura las variables de entorno en el archivo `.env`:
```
PRIVATE_KEY=tu_clave_privada
RPC_URL=https://sepolia.base.org
```

## Scripts

### Realizar swap de VCOP a USDC

Para realizar un swap de VCOP a USDC en Base Sepolia:

1. Asegúrate de que tu cuenta tiene suficientes tokens VCOP.
2. Ejecuta el siguiente comando:

```bash
# Cargar variables de entorno y ejecutar el script
source .env
forge script script/SwapVCOP.s.sol:SwapVCOPScript --rpc-url base-sepolia --private-key $PRIVATE_KEY --broadcast
```

El script está configurado para vender 49,000 VCOP por USDC. Si necesitas cambiar la cantidad, modifica la constante `SWAP_AMOUNT` en el archivo `script/SwapVCOP.s.sol`.

### Nota importante

- El script asume que VCOP tiene 6 decimales.
- Asegúrate de que la cuenta asociada a tu clave privada tiene suficientes tokens VCOP para realizar el swap.
- El script utiliza el PoolSwapTest contract de Uniswap V4 en Base Sepolia.

## Contratos usados

- PoolManager: 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408
- Universal Router: 0x492E6456D9528771018DeB9E87ef7750EF184104
- Position Manager: 0x4B2C77d209D3405F41a037Ec6c77F7F5b8e2ca80
- PoolSwapTest: 0x8B5bcC363ddE2614281aD875bad385E0A785D3B9
- VCOP Token: 0xd16Ee99c7EA2B30c13c3dC298EADEE00B870BBCC
- USDC Token: 0xE7a4113a8a497DD72D29F35E188eEd7403e8B2E8
- VCOP Rebase Hook: 0x866bf94370e8A7C9cDeAFb592C2ac62903e30040 