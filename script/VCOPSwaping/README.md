# VCOP Swap Script

Script para comprar o vender VCOP tokens en el pool de Uniswap v4.

## Configuración

Para realizar un swap, solo necesitas modificar el archivo `VCOPSwapConfig.sol` con tus parámetros deseados:

1. **Modo de operación**:
   - `_COMPRAR_VCOP = true`: Comprar VCOP con USDC
   - `_COMPRAR_VCOP = false`: Vender VCOP por USDC

2. **Cantidad a intercambiar**:
   - Si compras VCOP: cantidad de USDC a gastar
   - Si vendes VCOP: cantidad de VCOP a vender
   - Ejemplo: `_CANTIDAD = 1000 * 10**6` (1,000 tokens con 6 decimales)

3. **Slippage máximo** (opcional):
   - `_SLIPPAGE_MAX = 0`: impacto de precio ilimitado
   - Ejemplos:
     - `_SLIPPAGE_MAX = 50`: 0.5% máximo slippage
     - `_SLIPPAGE_MAX = 100`: 1% máximo slippage
     - `_SLIPPAGE_MAX = 1000`: 10% máximo slippage

## Ejecución

Para ejecutar el script:

```bash
source .env && forge script script/VCOPSwaping/SwapVCOP.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --legacy -vvvv
```

## Ejemplo

Para comprar VCOP con 500 USDC:

```solidity
// En VCOPSwapConfig.sol
_COMPRAR_VCOP = true;
_CANTIDAD = 500* 10**6; // 500 USDC
```

Para vender 2,000 VCOP:

```solidity
// En VCOPSwapConfig.sol
_COMPRAR_VCOP = false;
_CANTIDAD = 2000 * 10**6; // 2,000 VCOP
``` 