# Forge Gas Snapshot

Flexible, checked-in gas snapshotting for [Foundry](https://github.com/foundry-rs).

Forge has native gas reporting with `forge snapshot` and `forge test --gas-report`, but neither perfectly fit my needs. Specifically, `forge-gas-snapshot` aims to allow for:
- Gas reports over specific, known flows 
    - not entire tests and not an average of all calls
- Check gas diffs into version control
- See gas changes over time through commit history

# Installation
```solidity
forge install marktoda/forge-gas-snapshot
```

- NOTE: `ffi` must be enabled

# Usage

By default, gas snapshots are automatically written to `./forge-snapshots/<test-name>.snap` on run: 

```solidity
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";

contract MyTest is GasSnapshot {
    function test() public {
        snapStart("test name");
        // do stuff
        snapEnd();
    }
}
```

### Check Mode
Snapshots can be run in check-mode where they revert on mismatch by setting an environment variable `FORGE_SNAPSHOT_CHECK=true`


# TODO Improvements

- [ ] Introspection for file / function name
- [ ] Group related snapshots in a single file
- [ ] Check overhead and accuracy
- [ ] Env config for snap dir
