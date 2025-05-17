# ABIs Simplificados para VCOP

Este directorio contiene ABIs simplificados para los principales contratos del sistema VCOP Stablecoin. Estos ABIs han sido preparados para facilitar la integración en frontends y otras aplicaciones.

## Contratos Incluidos

### 1. VCOPCollateralManager (`simplified_abi_VCOPCollateralManager.json`)
Gestiona el sistema de colaterales para el stablecoin VCOP.

- **Funciones principales**:
  - `createPosition`: Crea una posición de colateral para acuñar VCOP
  - `addCollateral`: Añade más colateral a una posición existente
  - `withdrawCollateral`: Retira colateral de una posición si la ratio lo permite
  - `repayDebt`: Repaga deuda en VCOP y recupera colateral
  - `liquidatePosition`: Permite liquidar posiciones bajo-colateralizadas
  - `getCurrentCollateralRatio`: Obtiene la ratio de colateralización de una posición
  - `getMaxVCOPforCollateral`: Calcula el máximo VCOP que se puede acuñar con un colateral dado
  - `hasPSMReservesFor`: Verifica si el PSM tiene suficiente reserva para un colateral

### 2. VCOPCollateralized (`simplified_abi_VCOPCollateralized.json`)
Implementación del token VCOP con funcionalidad de acuñación controlada.

- **Funciones principales**:
  - `mint`: Acuña nuevos tokens VCOP (solo llamable por minters autorizados)
  - `burn`: Quema tokens VCOP
  - `transfer`, `transferFrom`, `approve`: Funciones ERC20 estándar
  - `setMinter`, `removeMinter`: Gestión de minters autorizados
  - `balanceOf`, `totalSupply`: Consulta de balances y oferta total

### 3. VCOPCollateralHook (`simplified_abi_VCOPCollateralHook.json`)
Hook para Uniswap v4 que gestiona la interacción con el sistema de colaterales.

- **Funciones principales**:
  - `swapUsdcForVcop`: Intercambia USDC por VCOP usando el PSM (Peg Stability Module)
  - `swapVcopForUsdc`: Intercambia VCOP por USDC usando el PSM
  - `provisionPSMWithLiquidity`: Proporciona liquidez al PSM
  - `setSpreadBps`: Configura el spread para intercambios en el PSM

### 4. VCOPOracle (`simplified_abi_VCOPOracle.json`)
Oráculo de precios para el tipo de cambio USD/COP y VCOP/USD.

- **Funciones principales**:
  - `getUsdToCopRate`: Obtiene el tipo de cambio USD/COP
  - `getVcopToUsdPrice`: Obtiene el precio de VCOP en USD
  - `updateUsdToCopRate`: Actualiza el tipo de cambio USD/COP
  - `emergencyPriceUpdate`: Permite actualizar el precio en situaciones de emergencia

### 5. VCOPPriceCalculator (`simplified_abi_VCOPPriceCalculator.json`)
Calcula el precio de VCOP y determina si está en paridad.

- **Funciones principales**:
  - `calculateVcopToCopRate`: Calcula la tasa VCOP/COP
  - `isAtParity`: Verifica si VCOP está en paridad con COP
  - `getVcopToUsdPrice`: Obtiene el precio de VCOP en USD
  - `setParityTolerance`: Configura el rango de tolerancia para la paridad

## Uso en Frontend

Para usar estos ABIs en una aplicación frontend:

```javascript
import collateralManagerABI from './simplified_abi_VCOPCollateralManager.json';
import vcopABI from './simplified_abi_VCOPCollateralized.json';

// Ejemplo de uso con ethers.js
const collateralManagerAddress = "0xd447eF9aB1DCC346a57EcdAB27F02C20e6d2dbF6";
const vcopAddress = "0xd1F263942EE26d34B56f50F05D59E84b10FF9fD1";

const collateralManager = new ethers.Contract(
  collateralManagerAddress,
  collateralManagerABI,
  provider
);

const vcop = new ethers.Contract(
  vcopAddress,
  vcopABI,
  provider
);

// Ejemplo de lectura de datos
async function checkBalance(userAddress) {
  const balance = await vcop.balanceOf(userAddress);
  console.log(`VCOP balance: ${ethers.utils.formatUnits(balance, 6)}`);
}

// Ejemplo de creación de posición de colateral
async function createPosition(collateralAmount, vcopToMint) {
  const usdcAddress = "0xE5964b67F1F121A54da973652F4B839C4F453Ca6";
  
  // Primero aprobar el gasto de USDC
  await usdc.approve(collateralManagerAddress, collateralAmount);
  
  // Luego crear la posición
  const tx = await collateralManager.createPosition(
    usdcAddress,
    collateralAmount,
    vcopToMint
  );
  
  await tx.wait();
  console.log("Posición creada exitosamente");
}
```

## Direcciones de Contratos Desplegados (Base Sepolia)

- USDC Simulado: `0xE5964b67F1F121A54da973652F4B839C4F453Ca6`
- VCOP Colateralizado: `0xd1F263942EE26d34B56f50F05D59E84b10FF9fD1`
- VCOP Oracle: `0x3618Ef53F8472d652AA8ab46381bcd15C053f867`
- VCOP Collateral Hook: `0x5255E0B8Cd682657d990613d0f08eA2f3B59c4C0`
- Collateral Manager: `0xd447eF9aB1DCC346a57EcdAB27F02C20e6d2dbF6`
- VCOP Price Calculator: `0x999653EEb3F93f50e9628Ddb65754540A20Af690` 