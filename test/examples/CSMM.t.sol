// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {CSMM} from "../../src/examples/CSMM.sol";
import {HookMiner} from "../utils/HookMiner.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract CSMMTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    CSMM hook;
    PoolId poolId;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        Deployers.deployFreshManagerAndRouters();
        Deployers.deployMintAndApprove2Currencies();

        // Deploy the hook to an address with the correct flags
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
        );
        (address hookAddress, bytes32 salt) =
            HookMiner.find(address(this), flags, type(CSMM).creationCode, abi.encode(address(manager)));
        hook = new CSMM{salt: salt}(IPoolManager(address(manager)));
        require(address(hook) == hookAddress, "CSMMTest: hook address mismatch");

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(address(hook)));
        poolId = key.toId();
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        // Provide external liquidity to the hook
        IERC20(Currency.unwrap(currency0)).approve(address(hook), 1000 ether);
        IERC20(Currency.unwrap(currency1)).approve(address(hook), 1000 ether);
        hook.addLiquidity(key, abi.encode(1000 ether));
    }

    function test_csmm(bool zeroForOne, int256 amountSpecified) public {
        amountSpecified = bound(amountSpecified, -1000e18, 1000e18);
        vm.assume(amountSpecified != 0);

        uint256 balance0Before = currency0.balanceOfSelf();
        uint256 balance1Before = currency1.balanceOfSelf();
        swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
        uint256 balance0After = currency0.balanceOfSelf();
        uint256 balance1After = currency1.balanceOfSelf();

        uint256 swapAmount = 0 < amountSpecified ? uint256(amountSpecified) : uint256(-amountSpecified);
        if (zeroForOne) {
            assertEq(balance0Before - balance0After, swapAmount);
            assertEq(balance1After - balance1Before, swapAmount);
        } else {
            assertEq(balance1Before - balance1After, swapAmount);
            assertEq(balance0After - balance0Before, swapAmount);
        }
    }
}
