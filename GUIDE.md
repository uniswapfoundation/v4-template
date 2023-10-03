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

The existing hook functions are simply counting how often a pool recieves a swap or a liquidity position modification.

```solidity
    function afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        override
        returns (bytes4)
    {
        afterSwapCount[key.toId()]++;
        return BaseHook.afterSwap.selector;
    }
```

```solidity
    function testCounterHooks() public {
        assertEq(counter.afterSwapCount(poolId), 0);

        // Perform a test swap //
        int256 amount = 100;
        bool zeroForOne = true;
        swap(poolKey, amount, zeroForOne);
        // ------------------- //

        assertEq(counter.afterSwapCount(poolId), 1);
    }
```

With the hook functions in mind, you're ready to start developing your own logic. Get started with modifying the hook function bodies.

```solidity
    function afterSwap(address sender, PoolKey calldata key, IPoolManager.SwapParams calldata params, BalanceDelta delta, bytes calldata hookData)
        external
        override
        returns (bytes4)
    {
        // -----------------------
        // DEFINE AND MODIFY LOGIC
        // -----------------------
        return BaseHook.afterSwap.selector;
    }

> A note on hook design

Hooks should service multiple trading pairs. One single hook contract, deployed once, should be able to serve both ETHUSDC and ETHUSDT for example

```

### The Tests

---

## Troubleshooting

## Conclusion and Future