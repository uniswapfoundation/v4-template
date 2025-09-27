// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {BaseHook} from "src/base/BaseHook.sol";
import {BaseHookMock, BaseHookMockReverts} from "test/mocks/BaseHookMock.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {ProtocolFeeLibrary} from "v4-core/src/libraries/ProtocolFeeLibrary.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {Pool} from "v4-core/src/libraries/Pool.sol";

contract BaseHookTest is Test, Deployers {
    event Swap(
        PoolId indexed poolId,
        address indexed sender,
        int128 amount0,
        int128 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick,
        uint24 fee
    );

    BaseHookMock hook;
    BaseHookMockReverts hookReverts;

    function setUp() public {
        deployFreshManagerAndRouters();

        hook = BaseHookMock(
            address(
                uint160(
                    Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                        | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
                        | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
                        | Hooks.BEFORE_DONATE_FLAG | Hooks.AFTER_DONATE_FLAG
                )
            )
        );
        deployCodeTo("test/mocks/BaseHookMock.sol:BaseHookMock", abi.encode(manager), address(hook));

        hookReverts = BaseHookMockReverts(address(0x1000000000000000000000000000000000003FF0));
        deployCodeTo("test/mocks/BaseHookMock.sol:BaseHookMockReverts", abi.encode(manager), address(hookReverts));

        deployMintAndApprove2Currencies();

        vm.label(Currency.unwrap(currency0), "currency0");
        vm.label(Currency.unwrap(currency1), "currency1");
    }

    function test_initialize_succeeds() public {
        vm.expectEmit(address(hook));
        emit BaseHookMock.BeforeInitialize();
        vm.expectEmit(address(hook));
        emit BaseHookMock.AfterInitialize();
        (key,) = initPool(currency0, currency1, IHooks(address(hook)), LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1);
    }

    function test_addLiquidity_succeeds() public {
        (key,) = initPool(currency0, currency1, IHooks(address(hook)), LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1);

        vm.expectEmit(address(hook));
        emit BaseHookMock.BeforeAddLiquidity();
        vm.expectEmit(address(hook));
        emit BaseHookMock.AfterAddLiquidity();
        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
    }

    function test_removeLiquidity_succeeds() public {
        (key,) = initPoolAndAddLiquidity(
            currency0, currency1, IHooks(address(hook)), LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1
        );

        vm.expectEmit(address(hook));
        emit BaseHookMock.BeforeRemoveLiquidity();
        vm.expectEmit(address(hook));
        emit BaseHookMock.AfterRemoveLiquidity();
        modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
    }

    function test_swap_succeeds() public {
        (key,) = initPoolAndAddLiquidity(
            currency0, currency1, IHooks(address(hook)), LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1
        );

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.expectEmit(address(hook));
        emit BaseHookMock.BeforeSwap();
        vm.expectEmit(address(hook));
        emit BaseHookMock.AfterSwap();

        swapRouter.swap(key, SWAP_PARAMS, testSettings, ZERO_BYTES);
    }

    function test_donate_succeeds() public {
        (key,) = initPoolAndAddLiquidity(
            currency0, currency1, IHooks(address(hook)), LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1
        );

        vm.expectEmit(address(hook));
        emit BaseHookMock.BeforeDonate();
        vm.expectEmit(address(hook));
        emit BaseHookMock.AfterDonate();

        donateRouter.donate(key, 1e18, 1e18, ZERO_BYTES);
    }

    function test_initialize_reverts() public {
        vm.expectRevert();
        (key,) =
            initPool(currency0, currency1, IHooks(address(hookReverts)), LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1);

        vm.prank(address(manager));
        vm.expectRevert(BaseHook.HookNotImplemented.selector);
        hookReverts.afterInitialize(address(this), key, SQRT_PRICE_1_1, 0);
    }

    function test_addLiquidity_reverts() public {
        vm.prank(address(manager));
        vm.expectRevert(BaseHook.HookNotImplemented.selector);
        hookReverts.beforeAddLiquidity(address(this), key, LIQUIDITY_PARAMS, ZERO_BYTES);

        vm.prank(address(manager));
        vm.expectRevert(BaseHook.HookNotImplemented.selector);
        hookReverts.afterAddLiquidity(
            address(this),
            key,
            LIQUIDITY_PARAMS,
            BalanceDeltaLibrary.ZERO_DELTA,
            BalanceDeltaLibrary.ZERO_DELTA,
            ZERO_BYTES
        );
    }

    function test_removeLiquidity_reverts() public {
        vm.prank(address(manager));
        vm.expectRevert(BaseHook.HookNotImplemented.selector);
        hookReverts.beforeRemoveLiquidity(address(this), key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);

        vm.prank(address(manager));
        vm.expectRevert(BaseHook.HookNotImplemented.selector);
        hookReverts.afterRemoveLiquidity(
            address(this),
            key,
            REMOVE_LIQUIDITY_PARAMS,
            BalanceDeltaLibrary.ZERO_DELTA,
            BalanceDeltaLibrary.ZERO_DELTA,
            ZERO_BYTES
        );
    }

    function test_swap_reverts() public {
        vm.prank(address(manager));
        vm.expectRevert(BaseHook.HookNotImplemented.selector);
        hookReverts.beforeSwap(address(this), key, SWAP_PARAMS, ZERO_BYTES);

        vm.prank(address(manager));
        vm.expectRevert(BaseHook.HookNotImplemented.selector);
        hookReverts.afterSwap(address(this), key, SWAP_PARAMS, BalanceDeltaLibrary.ZERO_DELTA, ZERO_BYTES);
    }

    function test_donate_reverts() public {
        vm.prank(address(manager));
        vm.expectRevert(BaseHook.HookNotImplemented.selector);
        hookReverts.beforeDonate(address(this), key, 1e18, 1e18, ZERO_BYTES);

        vm.prank(address(manager));
        vm.expectRevert(BaseHook.HookNotImplemented.selector);
        hookReverts.afterDonate(address(this), key, 1e18, 1e18, ZERO_BYTES);
    }

    function test_callback_succeeds() public {
        (key,) = initPoolAndAddLiquidity(
            currency0, currency1, IHooks(address(hook)), LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1
        );

        vm.expectEmit(address(hook));
        emit BaseHookMock.Callback();
        hook.callback(abi.encodeWithSelector(BaseHookMock._callback.selector, false));
    }

    function test_callback_notSelf_reverts() public {
        (key,) = initPoolAndAddLiquidity(
            currency0, currency1, IHooks(address(hook)), LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1
        );

        vm.expectRevert(BaseHook.NotSelf.selector);
        hook._callback(false);
    }

    function test_callback_error_reverts() public {
        (key,) = initPoolAndAddLiquidity(
            currency0, currency1, IHooks(address(hook)), LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1
        );

        vm.expectRevert(BaseHookMock.RevertCallback.selector);
        hook.callback(abi.encodeWithSelector(BaseHookMock._callback.selector, true));
    }

    function test_all_notPoolManager_reverts() public {
        vm.expectRevert(BaseHook.NotPoolManager.selector);
        hook.beforeInitialize(address(this), key, SQRT_PRICE_1_1);

        vm.expectRevert(BaseHook.NotPoolManager.selector);
        hook.afterInitialize(address(this), key, SQRT_PRICE_1_1, 0);

        vm.expectRevert(BaseHook.NotPoolManager.selector);
        hook.beforeAddLiquidity(address(this), key, LIQUIDITY_PARAMS, ZERO_BYTES);

        vm.expectRevert(BaseHook.NotPoolManager.selector);
        hook.afterAddLiquidity(
            address(this),
            key,
            LIQUIDITY_PARAMS,
            BalanceDeltaLibrary.ZERO_DELTA,
            BalanceDeltaLibrary.ZERO_DELTA,
            ZERO_BYTES
        );

        vm.expectRevert(BaseHook.NotPoolManager.selector);
        hook.beforeRemoveLiquidity(address(this), key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);

        vm.expectRevert(BaseHook.NotPoolManager.selector);
        hook.afterRemoveLiquidity(
            address(this),
            key,
            REMOVE_LIQUIDITY_PARAMS,
            BalanceDeltaLibrary.ZERO_DELTA,
            BalanceDeltaLibrary.ZERO_DELTA,
            ZERO_BYTES
        );

        vm.expectRevert(BaseHook.NotPoolManager.selector);
        hook.beforeSwap(address(this), key, SWAP_PARAMS, ZERO_BYTES);

        vm.expectRevert(BaseHook.NotPoolManager.selector);
        hook.afterSwap(address(this), key, SWAP_PARAMS, BalanceDeltaLibrary.ZERO_DELTA, ZERO_BYTES);

        vm.expectRevert(BaseHook.NotPoolManager.selector);
        hook.beforeDonate(address(this), key, 1e18, 1e18, ZERO_BYTES);

        vm.expectRevert(BaseHook.NotPoolManager.selector);
        hook.afterDonate(address(this), key, 1e18, 1e18, ZERO_BYTES);
    }

    function test_onlyValidPools_succeeds() public {
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: 0, tickSpacing: 0, hooks: IHooks(address(0x123))});

        vm.prank(address(manager));
        vm.expectRevert(BaseHook.InvalidPool.selector);
        hook.beforeSwap(address(this), key, SWAP_PARAMS, ZERO_BYTES);
    }
}
