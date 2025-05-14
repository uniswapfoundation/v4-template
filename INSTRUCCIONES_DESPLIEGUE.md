# Instrucciones para Despliegue Seguro del Sistema VCOP

Para ejecutar el despliegue en dos partes, siga estos pasos:

## 1. Desplegar Contratos Base

```bash
forge script script/DeployVCOPBase.sol:DeployVCOPBase --via-ir --broadcast --fork-url https://sepolia.base.org
```

Este comando desplegará:
- USDC simulado
- Token VCOP
- Oráculo VCOP
- Collateral Manager

## 2. Configurar el Sistema

```bash
forge script script/ConfigureVCOPSystem.sol:ConfigureVCOPSystem --via-ir --broadcast --fork-url https://sepolia.base.org
```

Este segundo comando configurará:
- El hook de Uniswap v4
- Las referencias cruzadas entre contratos
- Los colaterales y parámetros del sistema
- El pool de Uniswap v4 y la liquidez inicial
- El módulo de estabilidad del precio (PSM)

## Ventajas de esta separación

1. **Mayor seguridad**: Se reduce el riesgo de problemas con las claves privadas al limitar el alcance de cada script.
2. **Mejor recuperación ante errores**: Si hay un problema en la segunda parte, no es necesario redesplegar todos los contratos.
3. **Claridad del código**: Cada script tiene una responsabilidad bien definida.
4. **Control de permisos**: El segundo script verifica los propietarios antes de proceder con la configuración. 