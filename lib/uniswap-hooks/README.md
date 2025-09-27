# <img src="logo.svg" alt="Uniswap Hooks" height="40px">

[![Coverage Status](https://codecov.io/gh/OpenZeppelin/uniswap-hooks/graph/badge.svg)](https://codecov.io/gh/OpenZeppelin/uniswap-hooks)
[![CI](https://github.com/OpenZeppelin/uniswap-hooks/actions/workflows/checks.yml/badge.svg)](https://github.com/OpenZeppelin/uniswap-hooks/actions/workflows/checks.yml)

Solidity library for secure and modular Uniswap hooks.

> [!WARNING]
> This is **experimental software** and is provided on an "as is" and "as available" basis. We **do not give any warranties** and **will not be liable for any losses** incurred through any use of this code base. Read the [disclaimer](#disclaimer) for more information.

## Overview

### Installation

#### Foundry

> [!WARNING]
> Foundry installs the latest version initially, but subsequent `forge update` commands will use the `master` branch.

```
$ forge install OpenZeppelin/uniswap-hooks
```

Add `@openzeppelin/uniswap-hooks/=lib/uniswap-hooks/src/` in `remappings.txt`.
#### Hardhat

Not currently supported given that Uniswap v4 core and periphery contracts are not yet npm packages.

## Contribute

There are many ways you can participate and help build high quality software. Check out the [contribution guide](CONTRIBUTING.md)!

## License

OpenZeppelin Uniswap Hooks is released under the [MIT License](LICENSE).

## Legal

Your use of this Project is governed by the terms found at www.openzeppelin.com/tos (the "Terms").

## Disclaimer

The hook code provided herein is offered on an “as-is” basis and has not been audited for security, reliability, or compliance with any specific standards or regulations. It may contain bugs, errors, or vulnerabilities that could lead to unintended consequences. By utilizing these hooks, you acknowledge and agree that:

- Assumption of Risk: You assume all responsibility and risks associated with its use.
- No Warranty: The authors and distributors of this code disclaim all warranties, express or implied, including but not limited to warranties of merchantability, fitness for a particular purpose, and non-infringement.
- Limitation of Liability: In no event shall the authors or distributors be held liable for any damages or losses, including but not limited to direct, indirect, incidental, or consequential damages arising out of or in connection with the use or inability to use the code.

Recommendation: Users are strongly encouraged to review, test, and, if necessary, audit the hooks independently before deploying in any environment.

By proceeding to utilize these hooks, you indicate your understanding and acceptance of this disclaimer.