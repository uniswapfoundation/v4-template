# Getting started with `v4-template`

## Introduction

When Uniswap Labs previewed v4, the limitless flexibility of hooks stirred a million different ideas. From trading order types, to oracles, to bizarre permissioned trading, Uniswap v4 opens up an entirely new programming space for developers. To quickly experiment, iterate, and test ideas, having a starter template goes a long way. 

`v4-template` particulary focuses on providing clean abstractions while being minimally lightweight and unopinonated. Overall, it reduces developer friction by defining:

* A minimal hook contract with swap and modifyPosition hooks
* Some test setup - deploys the v4 PoolManager, test tokens, the router contracts, and the hook
* A deployment script for local and testnet deployments

By covering the basics, hook developers can start and validate what matters most -- the hook logic

## Setup

To use the template, all that is required is the [foundry toolkit](https://book.getfoundry.sh)

and then using this link, or this button, anyone can create a new repo from the template

With the repo cloned locally, you can install the Uniswap v4 codebase:
```bash
forge install
```

To verify correct setup:
```bash
forge test

# output:
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

The template provides three primary files to boostrap hook development

```
v4-template
├── script
│   └── Counter.s.sol      // Deployment script
├── src
│   └── Counter.sol        // Hook contract
└── test
    ├── Counter.t.sol      // Tests
    └── utils
        └── ...
```

### `Counter.sol` - the Hook Contract

The contract defines `beforeSwap`, `afterSwap`, `beforeModifyPosition`, and `afterModifyPosition`. These hook functions are not mandatory, and any combination of hooks can be used

> Don't forget hooks for `initialize` and `donate` are also available!

The provided hook functions are simply counting how often a pool recieves a swap or an LP modification

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
        assertEq(counter.afterSwapCount(poolKey.toId()), 0);

        // Perform a test swap //
        int256 amount = 100;
        bool zeroForOne = true;
        swap(poolKey, amount, zeroForOne);
        // ------------------- //

        assertEq(counter.afterSwapCount(poolKey.toId()), 1);
    }
```

<details>
  <summary>Specifying Hook functionality</summary>
  
  ### Specifying Hook functionality
  To communicate which hook functions are implemented, the Hook contract will return the information with `getHookCalls()`

  If hook implements `afterSwap` and `afterModifyPosition`:
  ```solidity
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

  and update the flags during test deployment:
  ```solidity
  uint160 flags = uint160(
    Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_MODIFY_POSITION_FLAG
  );
  ```
</details>


You're ready to start developing your own logic! Get started with modifying the hook function bodies:

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
```

<details>
  <summary>A note on hook design</summary>
  
  ### Hooks should also be singletons!
  A hook contract should service multiple trading pairs. One single hook contract, deployed once, should be able to serve both ETH/USDC and ETH/USDT

  To support multiple trading pairs/pools, most state variables should be stored in a **mapping** -- keyed by the `PoolId` type. This is the case for the `Counter` hook, which stores the swap count for *each pool*

  ```solidity
  mapping(uint256 => uint256) public afterSwapCount;
  ```
</details>


### Testing

Unit tests will be the easiest way to validate your hook behavior. The template's provided test file setups external dependencies -- the v4 PoolManager, test tokens, swap routers, LP router, etc

All you need to do is

1. Deploy the hook
2. Create a pool with the hook
3. Provide liquidity to the pool
4. Perform a swap

See [Counter.t.sol](https://github.com/saucepoint/v4-template/blob/main/test/Counter.t.sol) for more
```solidity
function setUp() public {
    // creates the pool manager, test tokens, and other utility routers
    HookTest.initHookTestEnv();

    // Deploy the hook to an address with the correct flags
    uint160 flags = uint160(
        Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_MODIFY_POSITION_FLAG
            | Hooks.AFTER_MODIFY_POSITION_FLAG
    );
    (address hookAddress, bytes32 salt) =
        HookMiner.find(address(this), flags, 0, type(Counter).creationCode, abi.encode(address(manager)));
    counter = new Counter{salt: salt}(IPoolManager(address(manager)));
    require(address(counter) == hookAddress, "CounterTest: hook address mismatch");

    // Create the pool
    poolKey = PoolKey(Currency.wrap(address(token0)), Currency.wrap(address(token1)), 3000, 60, IHooks(counter));
    manager.initialize(poolKey, SQRT_RATIO_1_1, ZERO_BYTES);

    // Provide liquidity to the pool (full range)
    modifyPositionRouter.modifyPosition(
        poolKey, IPoolManager.ModifyPositionParams(TickMath.minUsableTick(60), TickMath.maxUsableTick(60), 10 ether)
    );
}

function testCounterHooks() public {
    assertEq(counter.beforeSwapCount(poolId), 0);
    assertEq(counter.afterSwapCount(poolId), 0);

    // Perform a test swap //
    int256 amount = 100;
    bool zeroForOne = true;
    swap(poolKey, amount, zeroForOne);
    // ------------------- //

    assertEq(counter.beforeSwapCount(poolId), 1);
    assertEq(counter.afterSwapCount(poolId), 1);
}
```

---

## Troubleshooting


### Permission Denied

When installing dependencies with `forge install`, Github may throw a `Permission Denied` error

This is typically caused by Github SSH keys, and can be resolved by following the steps [here](https://docs.github.com/en/github/authenticating-to-github/connecting-to-github-with-ssh) or adding the keys to your ssh-agent, [here](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent#adding-your-ssh-key-to-the-ssh-agent)

### Hook deployment failures



## Conclusion and Future

With this guide, you should be able to quickly start your hook development journey. Hooks are intentionally ambigious and open-ended, so I hope the template can get you started on what matters most without getting in the way.

Even if `v4-template` is not for you, and you prefer rolling-your-own environment, I hope that the template offers examples during the Hook development process:

* Hook Contract
* Hook contract deployment (for local testing, or testnets)
* Initialize a Pool with the Hook
* Provisioning Liquidity
* Performing a swap

Feedback and contributions are always welcome. For now, the template will strive to stay up to date with the latest v4 changes. And as new best-practices arise, expect the template to reflect and enshrine these patterns