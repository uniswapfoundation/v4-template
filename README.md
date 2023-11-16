# v4-template
### **A template for writing Uniswap v4 Hooks 🦄**

[`Use this Template`](https://github.com/saucepoint/v4-template/generate)

1. The example hook [Counter.sol](src/Counter.sol) demonstrates the `beforeSwap()` and `afterSwap()` hooks
2. The test template [Counter.t.sol](test/Counter.t.sol) preconfigures the v4 pool manager, test tokens, and test liquidity.
3. The scripts in the v4-template are written so that you can
   - Designed for Goerli, but usable for other networks
   - Deploy a hook contract
   - Create a liquidity pool on V4
   - Add liquidity to a pool
   - Swap tokens on a pool
6. This template is built using Foundry

<details>
<summary><b>NOTE: v4-core versioning</b></summary>

Previous versions of `v4-template` accessed `v4-core` as the nested dependency of `v4-periphery`. With recent core activity, `v4-periphery` is slightly out of sync.

As of 11/16/2023, `v4-template` has pinned a version of `v4-core` that is most similar to the testnet deployments.

If there are issues, please do not hesistate on reaching out to [saucepoint](https://t.me/saucepoint)

</details>

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
forge script script/Anvil.s.sol \
    --rpc-url http://localhost:8545 \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    --code-size-limit 30000 \
    --broadcast
```

<details>
<summary><h3>Goerli Testnet</h3></summary>

For testing on Goerli Testnet the Uniswap Foundation team has deployed a slimmed down version of the V4 contract (due to current contract size limits) on the network.

The relevant addresses for testing on Goerli are the ones below

```bash
POOL_MANAGER = 0x3A9D48AB9751398BbFa63ad67599Bb04e4BdF98b
POOL_MODIFY_POSITION_TEST = 0x83feDBeD11B3667f40263a88e8435fca51A03F8C
SWAP_ROUTER = 0xF8AADC65Bf1Ec1645ef931317fD48ffa734a185c
```

Update the following command with your own private key:

```
forge script script/00_Counter.s.sol \
--rpc-url https://rpc.ankr.com/eth_goerli \
--private-key [your_private_key_on_goerli_here] \
--broadcast
```

### *Deploying your own Tokens For Testing*

Because V4 is still in testing mode, most networks don't have liquidity pools live on V4 testnets. We recommend launching your own test tokens and expirementing with them that. We've included in the templace a Mock UNI and Mock USDC contract for easier testing. You can deploy the contracts and when you do you'll have 1 million mock tokens to test with for each contract. See deployment commands below

```
forge create script/mocks/mUNI.sol:MockUNI \
--rpc-url [your_rpc_url_here] \
--private-key [your_private_key_on_goerli_here]
```

```
forge create script/mocks/mUSDC.sol:MockUSDC \
--rpc-url [your_rpc_url_here] \
--private-key [your_private_key_on_goerli_here]
```

</details>

---

<details>
<summary><h2>Troubleshooting</h2></summary>



### *Permission Denied*

When installing dependencies with `forge install`, Github may throw a `Permission Denied` error

Typically caused by missing Github SSH keys, and can be resolved by following the steps [here](https://docs.github.com/en/github/authenticating-to-github/connecting-to-github-with-ssh) 

Or [adding the keys to your ssh-agent](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent#adding-your-ssh-key-to-the-ssh-agent), if you have already uploaded SSH keys

### Hook deployment failures

Hook deployment failures are caused by incorrect flags or incorrect salt mining

1. Verify the flags are in agreement:
    * `getHookCalls()` returns the correct flags
    * `flags` provided to `HookMiner.find(...)`
2. Verify salt mining is correct:
    * In **forge test**: the *deploye*r for: `new Hook{salt: salt}(...)` and `HookMiner.find(deployer, ...)` are the same. This will be `address(this)`. If using `vm.prank`, the deployer will be the pranking address
    * In **forge script**: the deployer must be the CREATE2 Proxy: `0x4e59b44847b379578588920cA78FbF26c0B4956C`
        * If anvil does not have the CREATE2 deployer, your foundry may be out of date. You can update it with `foundryup`

</details>

---

Additional resources:

[v4-periphery](https://github.com/uniswap/v4-periphery) contains advanced hook implementations that serve as a great reference

[v4-core](https://github.com/uniswap/v4-core)

