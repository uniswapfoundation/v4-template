# Hookmate

Hookmate is a library designed to simplify Uniswap v4 hook development. It provides reusable libraries and utilities to accelerate building custom hooks for Uniswap v4 pools.

The library itself does not provide a version of `v4-core` or `v4-periphery`, so you will need to install those separately. This allows you to use the latest versions of those libraries without being tied to a specific version.

## Features

Hookmate includes the following:

- **Artifacts**: Pre-built artifacts are included for `V4PoolManager`, `V4PositionManager`, `Permit2` and `V4Router`. This way, you can always use the canonical versions of these without being locked to the same Solidity version.
- **Constants**: Includes common address constants for easier integration with `PoolManager`, `PositionManager`, `Permit2` and `V4Router`.
- **Deploy Helper**: Utilities for deploying and managing utilities, hooks and artifacts.
- **Interfaces**: Additionally includes interfaces the following for easier access: `V4Router`

## Usage

You can directly import `hookmate` via Git Submodules or NPM Package Managers. The default `v4-template` already includes `hookmate` as a foundry module.

## Contributing

Contributions are welcome! Please open issues or submit pull requests for improvements.

## License

This code is licensed under the MIT License.
