# v4-template
### **A template for writing Uniswap v4 Hooks 🦄**

[`Use this Template`](https://github.com/saucepoint/v4-template/generate)

1. The example hook [Counter.sol](src/Counter.sol) demonstrates the `beforeSwap()` and `afterSwap()` hooks
2. The test template [Counter.t.sol](test/Counter.t.sol) preconfigures the v4 pool manager, test tokens, and test liquidity.

---

### Local Development (Anvil)

*requires [foundry](https://book.getfoundry.sh)*

```
forge install
forge test
```

Because v4 exceeds the bytecode limit of Ethereum and it's *business licensed*, we can only deploy & test hooks on [anvil](https://book.getfoundry.sh/anvil/).

```bash
# start anvil, with a larger code limit
anvil --code-size-limit 30000

# in a new terminal
forge script script/Counter.s.sol \
    --rpc-url http://localhost:8545 \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    --code-size-limit 30000 \
    --broadcast
```

---

## Troubleshooting


### *Permission Denied*

When installing dependencies with `forge install`, Github may throw a `Permission Denied` error

Typically caused by missing Github SSH keys, and can be resolved by following the steps [here](https://docs.github.com/en/github/authenticating-to-github/connecting-to-github-with-ssh) 

Or [adding the keys to your ssh-agent](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent#adding-your-ssh-key-to-the-ssh-agent), if you have already uploaded SSH keys

### Hook deployment failures

Hook deployment failures are caused by incorrect flags or incorrect salt mining

1. Verify the flags are in agreement:
    * `getHookCalls()` returns the correct flags
    * `flags` provided to `HookMiner.find(...)`
    * In obscure cases where you're deploying multiple hooks (with the same flags), try setting `seed=1000` for ` HookMiner.find`
2. Verify salt mining is correct:
    * In **forge test**: the *deploye*r for: `new Hook{salt: salt}(...)` and `HookMiner.find(deployer, ...)` are the same. This will be `address(this)`. If using `vm.prank`, the deployer will be the pranking address
    * In **forge script**: the deployer must be the CREATE2 Proxy: `0x4e59b44847b379578588920cA78FbF26c0B4956C`
        * If anvil does not have the CREATE2 deployer, your foundry may be out of date. You can update it with `foundryup`

---

Additional resources:

[v4-periphery](https://github.com/uniswap/v4-periphery) contains advanced hook implementations that serve as a great reference

[v4-core](https://github.com/uniswap/v4-core)

