# Getting started with `v4-template`

## Introduction

When Uniswap Labs previewed v4, the limitless flexibility of hooks stirred a million different ideas. Anywhere from trading order types, to oracles, to bizarre permissioned trading, v4 opens up a new space for developers. To quickly experiment, iterate, and test ideas, a template would go a long way. 

`v4-template` particulary focuses on providing clean abstractions while being minimally lightweight and unopinonated. Overall it reduces developer friction by providing:

* A minimal hook contract with swap and modifyPosition hooks
* Test setup. Deploys the v4 PoolManager, router contracts, and the hook
* Deployment script for local and testnet deployments

## Setup

To use the template, all that is required is the [foundry toolkit](https://book.getfoundry.sh)

and then using this link, or this button will create a new repo from the template

With the repo cloned locally, you can install the Uniswap v4 codebase with 

```bash
forge install
```

Verify proper set up

```bash
forge test
```

```bash
[⠢] Compiling...
[⠃] Compiling 3 files with 0.8.20
[⠊] Solc 0.8.20 finished in 2.72s
Compiler run successful!

Running 1 test for test/Counter.t.sol:CounterTest
[PASS] testCounterHooks() (gas: 218915)
Test result: ok. 1 passed; 0 failed; 0 skipped; finished in 16.68ms
 
Ran 1 test suites: 1 tests passed, 0 failed, 0 skipped (1 total tests)
```

---

## Developing your first hook

The template provides three primary files to boostrap hook development.

```
v4-template
├── script
│   └── Counter.s.sol      // Deployment script
├── src
│   └── Counter.sol        // Hook contract
└── test
    ├── Counter.t.sol      // Tests
    └── utils
        ├── HookMiner.sol
        └── HookTest.sol
```



### The Hook Contract

The main file to edit is `src/Counter.sol`. The contract defines `beforeSwap`, `afterSwap`, `beforeModifyPosition`, and `afterModifyPosition`. These are not explicitly required by any means, and any combination of hooks can be used.

> Note: Don't forget to update the function:

```solidity
    // i.e. hook depends on afterSwap and afterModifyPosition
    function getHooksCalls() public pure override returns (Hooks.Calls memory) {
        return Hooks.Calls({
            beforeInitialize: false,
            afterInitialize: false,
            beforeModifyPosition: false,
            afterModifyPosition: true,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false
        });
    }
```



### The Tests

---

## Troubleshooting

## Conclusion and Future