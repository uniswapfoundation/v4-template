# VCOP Stablecoin Colateralizada

Sistema de stablecoin respaldada por colateral anclada al peso colombiano (COP), construida sobre Uniswap v4.

## Arquitectura del Sistema

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────────┐
│ VCOPCollateral  │◄───┤ VCOPCollateral  │◄───┤ VCOPCollateralHook  │
│ (ERC20 Token)   │    │ Manager         │    │ (Uniswap v4 Hook)   │
└────────┬────────┘    └────────┬────────┘    └──────────┬──────────┘
         │                      │                        │
         │                      │                        │
         │                      │                        │
┌────────▼────────┐    ┌────────▼────────┐    ┌──────────▼──────────┐
│ Mock Tokens     │    │ VCOPOracle      │    │ Uniswap v4          │
│ (USDC, etc)     │    │                 │    │ Pool                │
└─────────────────┘    └────────┬────────┘    └─────────────────────┘
                                │
                       ┌────────▼────────┐
                       │ VCOPPrice       │
                       │ Calculator      │
                       └─────────────────┘
```

## Componentes Principales

### VCOPCollateralized.sol
- Token ERC20 con 6 decimales (compatible con USDC)
- Permisos especiales para minting/burning controlados por el manager
- Mecanismo de estabilidad basado en colateralización en lugar de rebases

### VCOPCollateralManager.sol
- Gestiona posiciones de colateral para usuarios
- Permite crear/modificar/cerrar posiciones
- Maneja liquidaciones de posiciones sub-colateralizadas
- Implementa el Peg Stability Module (PSM)

### VCOPCollateralHook.sol
- Hook de Uniswap v4 que monitorea precios
- Activa mecanismos de estabilidad cuando el precio se desvía
- Integra con el sistema colateral para intervenciones automáticas
- Permite operaciones de intercambio directo a través del PSM

### VCOPOracle.sol
- Proporciona tasas de cambio VCOP/COP y USD/COP
- Utiliza el pool de Uniswap v4 como fuente primaria de precios
- Interfaz común para todo el sistema

### VCOPPriceCalculator.sol
- Calcula precios exactos a partir de datos de Uniswap v4
- Determina si VCOP está en paridad con COP
- Proporciona funciones auxiliares para el sistema

## Workflow de Despliegue

### PASO 1: Desplegar USDC Simulado
- Desplegar MockERC20 como USDC para entorno de pruebas
- Acuñar cantidad inicial para el desplegador

### PASO 2: Desplegar Token VCOPCollateralized
- Implementar el token ERC20 con 6 decimales
- Configurar permisos iniciales (owner como minter/burner)

### PASO 3: Desplegar Oráculo y Calculador de Precios
- Desplegar VCOPOracle con tasa inicial USD/COP (4200)
- Desplegar VCOPPriceCalculator
- Configurar el calculador en el oráculo

### PASO 4: Desplegar Hook con HookMiner
- Calcular dirección con flags correctos (BEFORE_SWAP, AFTER_SWAP, AFTER_ADD_LIQUIDITY)
- Desplegar hook en la dirección calculada
- Inicializar con referencias a poolManager y oracle

### PASO 5: Desplegar VCOPCollateralManager
- Implementar el gestor de colateral
- Conectarlo con el token VCOP y oráculo
- Configurar hook con referencia al manager
- Configurar token con referencia al manager

### PASO 6: Configurar Colaterales y Permisos
- Registrar USDC como colateral aceptado
- Establecer ratios de colateralización (150%)
- Configurar umbrales de liquidación (120%)
- Asignar permisos de mint/burn al manager

### PASO 7: Crear Pool y Añadir Liquidez de Trading
- Crear PoolKey para el par VCOP/USDC con el hook
- Calcular precio inicial (1 VCOP = 1/4200 USDC)
- Inicializar pool con precio calculado
- Añadir liquidez inicial para trading

### PASO 8: Provisión de Liquidez al Sistema Colateral
- Transferir USDC al sistema colateral
- Acuñar VCOP inicial para el PSM
- Configurar parámetros del PSM (fees, límites)
- Inicializar fondos de estabilidad

## Parámetros de Configuración

| Parámetro | Valor | Descripción |
|-----------|-------|-------------|
| **Tasa Inicial USD/COP** | 4200 * 10^6 | 4200 COP = 1 USD |
| **Ratio de Colateralización** | 150% | Para cada 1 VCOP se requiere colateral valorado en 1.5 COP |
| **Liquidation Threshold** | 120% | Por debajo de este ratio, las posiciones pueden ser liquidadas |
| **PSM Fee** | 0.1% | Comisión por usar el módulo de estabilidad |
| **Pool Fee** | 0.3% | Comisión de Uniswap v4 para swaps |
| **Bandas de Paridad** | ±1% | Rango permitido de fluctuación del precio |

## Liquidez Inicial

| Componente | USDC | VCOP | Ratio |
|------------|------|------|-------|
| **Pool de Trading** | 100,000 | 420,000,000 | 1:4200 |
| **Sistema Colateral (PSM)** | 100,000 | 420,000,000 | 1:4200 |
| **Reserva de Emergencia** | 10,000 | - | - |

## Uso del Sistema

### Crear Posición Colateralizada
```solidity
// Aprobar transferencia de colateral
IERC20(usdcAddress).approve(address(collateralManager), 1000e6);

// Crear posición con 1000 USDC como colateral
collateralManager.createPosition(usdcAddress, 1000e6, 600e6); // Obtener 600 VCOP
```

### Repagar Deuda y Recuperar Colateral
```solidity
// Aprobar transferencia de VCOP para repago
IERC20(vcopAddress).approve(address(collateralManager), 600e6);

// Repagar deuda
collateralManager.repayDebt(positionId, 600e6);
```

### Intercambiar mediante PSM
```solidity
// Intercambiar VCOP por USDC usando el PSM
IERC20(vcopAddress).approve(address(hook), 100e6);
hook.psmSwapVCOPForCollateral(100e6);

// Intercambiar USDC por VCOP usando el PSM
IERC20(usdcAddress).approve(address(hook), 0.02381e6); // 0.02381 USDC ≈ 100 VCOP
hook.psmSwapCollateralForVCOP(0.02381e6);
```

## Ventajas sobre Sistema de Rebase

1. **Mayor transparencia**: Los usuarios tienen visibilidad total de su respaldo colateral
2. **Control de riesgo**: Ratios de colateralización configurables para diferentes activos
3. **Escalabilidad**: Soporte para múltiples tipos de colateral
4. **Resistencia a volatilidad**: Amortiguación de cambios bruscos mediante el PSM
5. **Integración con DeFi**: Compatible con aplicaciones DeFi estándar sin problemas de rebase

## Comandos de Despliegue

```shell
# Preparar variables de entorno
export PRIVATE_KEY=0x...
export POOL_MANAGER_ADDRESS=0x...
export POSITION_MANAGER_ADDRESS=0x...

# Ejecutar script de despliegue
forge script script/DeployVCOPCollateral.sol:DeployVCOPCollateral \
  --via-ir \
  --broadcast \
  --fork-url https://sepolia.base.org
``` 