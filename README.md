# VCOP Stablecoin Algorítmica con Hooks de Uniswap v4

Este proyecto implementa una stablecoin algorítmica llamada VCOP utilizando Hooks de Uniswap v4 para mantener automáticamente su precio cercano a $1 USD a través de un mecanismo de rebase.

## Descripción

VCOP es una stablecoin algorítmica que utiliza un mecanismo de rebase inspirado en protocolos como Ampleforth. El sistema ajusta automáticamente el suministro total de tokens VCOP basándose en las desviaciones de precio:

- Si VCOP > $1.05: Se ejecuta un rebase positivo (expansión del suministro)
- Si VCOP < $0.95: Se ejecuta un rebase negativo (contracción del suministro)
- Si $0.95 ≤ VCOP ≤ $1.05: No se realiza ningún rebase

El sistema aprovecha los hooks de Uniswap v4 para monitorear el precio después de cada swap y ejecutar rebases cuando sea necesario.

## Componentes Principales

El sistema consta de los siguientes componentes:

1. **VCOPRebased.sol**: Implementación de la stablecoin con mecanismo de rebase. Utiliza un sistema de "gons" para rastrear balances de manera proporcional durante los rebases.

2. **VCOPOracle.sol**: Oráculo que proporciona el precio de referencia para VCOP. En un entorno de producción, se reemplazaría por un oráculo descentralizado como Chainlink.

3. **VCOPRebaseHook.sol**: Hook de Uniswap v4 que monitorea los swaps y ejecuta rebases automáticamente cuando es necesario.

4. **Scripts de Despliegue**: Scripts para desplegar la stablecoin y sus componentes en diferentes entornos.

## Algoritmo de Rebase

El algoritmo de rebase funciona de la siguiente manera:

1. Después de cada swap en un pool que incluya VCOP, el hook verifica si el tiempo mínimo entre rebases ha pasado.
2. Si es el momento adecuado, el hook consulta el oráculo para obtener el precio actual de VCOP.
3. Si el precio está fuera del rango objetivo, se ejecuta un rebase:
   - Expansión: Si el precio es alto, se aumenta el suministro en un porcentaje fijo.
   - Contracción: Si el precio es bajo, se reduce el suministro en un porcentaje fijo.
4. Los balances de todos los usuarios se ajustan proporcionalmente.

## Configuración del Proyecto

### Requisitos

- [Foundry](https://github.com/foundry-rs/foundry)
- [Node.js](https://nodejs.org/) (opcional)

### Instalación

```bash
# Clonar el repositorio
git clone https://github.com/tuusuario/VCOPstablecoin.git
cd VCOPstablecoin

# Instalar dependencias
forge install
```

### Compilación

```bash
forge build
```

### Tests

```bash
forge test
```

### Despliegue

Para desplegar en una red de producción:

```bash
forge script script/DeployVCOP.s.sol:DeployVCOP --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

Para desplegar en un entorno de desarrollo local:

```bash
forge script script/DeployVCOP.s.sol:DeployVCOPDev --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

## Licencia

Este proyecto está licenciado bajo la Licencia MIT. Ver el archivo `LICENSE` para más detalles. 