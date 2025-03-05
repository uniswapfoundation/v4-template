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
import {Counter} from "../src/Counter.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";
import {IHookMetadata} from "v4-periphery/src/interfaces/IHookMetadata.sol";
import {IEIP7512} from "v4-periphery/src/interfaces/IEIP7512.sol";

contract CounterTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    event AuditSummaryRegistered(uint256 indexed auditId, bytes32 auditHash, string auditUri);

    Counter hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        deployAndApprovePosm(manager);

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                    | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(manager); //Add all the necessary constructor arguments from the hook
        deployCodeTo("Counter.sol:Counter", constructorArgs, flags);
        hook = Counter(flags);

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(key.tickSpacing);
        tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        uint128 liquidityAmount = 100e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = posm.mint(
            key,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            ZERO_BYTES
        );
    }

    function testCounterHooks() public {
        // positions were created in setup()
        assertEq(hook.beforeAddLiquidityCount(poolId), 1);
        assertEq(hook.beforeRemoveLiquidityCount(poolId), 0);

        assertEq(hook.beforeSwapCount(poolId), 0);
        assertEq(hook.afterSwapCount(poolId), 0);

        // Perform a test swap //
        bool zeroForOne = true;
        int256 amountSpecified = -1e18; // negative number indicates exact input swap!
        BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
        // ------------------- //

        assertEq(int256(swapDelta.amount0()), amountSpecified);

        assertEq(hook.beforeSwapCount(poolId), 1);
        assertEq(hook.afterSwapCount(poolId), 1);
    }

    function testLiquidityHooks() public {
        // positions were created in setup()
        assertEq(hook.beforeAddLiquidityCount(poolId), 1);
        assertEq(hook.beforeRemoveLiquidityCount(poolId), 0);

        // remove liquidity
        uint256 liquidityToRemove = 1e18;
        posm.decreaseLiquidity(
            tokenId,
            liquidityToRemove,
            MAX_SLIPPAGE_REMOVE_LIQUIDITY,
            MAX_SLIPPAGE_REMOVE_LIQUIDITY,
            address(this),
            block.timestamp,
            ZERO_BYTES
        );

        assertEq(hook.beforeAddLiquidityCount(poolId), 1);
        assertEq(hook.beforeRemoveLiquidityCount(poolId), 1);
    }

    function test_HookMetadata_auditSummaries_shouldRevert() external {
        vm.expectRevert(IHookMetadata.WrongAuditId.selector);
        hook.auditSummaries(0);

        vm.expectRevert(IHookMetadata.WrongAuditId.selector);
        hook.auditSummaries(100);
    }

    function test_PointsHookWithMetadata_registerAuditSummary() external {
        IEIP7512.SignedAuditSummary memory _signedAuditSummary = IEIP7512.SignedAuditSummary({
            summary: IEIP7512.AuditSummary({
                auditor: IEIP7512.Auditor({name: "Auditor", uri: "https://example.com/auditor", authors: new string[](2)}),
                issuedAt: block.timestamp,
                ercs: new uint256[](3),
                bytecodeHash: "0x1234567890abcdef",
                auditHash: "0x1234567890abcdef",
                auditUri: "https://example.com/audit"
            }),
            signedAt: block.timestamp,
            auditorSignature: IEIP7512.Signature({
                signatureType: IEIP7512.SignatureType.SECP256K1,
                data: abi.encode("Signature data")
            })
        });

        _signedAuditSummary.summary.auditor.authors[0] = "Author 1";
        _signedAuditSummary.summary.auditor.authors[1] = "Author 2";
        _signedAuditSummary.summary.ercs[0] = 1;
        _signedAuditSummary.summary.ercs[1] = 2;
        _signedAuditSummary.summary.ercs[2] = 3;

        vm.expectEmit(true, true, true, true, address(hook));

        emit AuditSummaryRegistered(
            hook.auditsCount(), _signedAuditSummary.summary.auditHash, _signedAuditSummary.summary.auditUri
        );

        uint256 _auditId = hook.registerAuditSummary(_signedAuditSummary);

        assertEq(hook.auditsCount(), 1);
        assertEq(_auditId, hook.auditsCount() - 1);

        Counter.SignedAuditSummary memory _retrievedAuditSummary = hook.auditSummaries(_auditId);

        assertEq(_retrievedAuditSummary.summary.auditor.name, _signedAuditSummary.summary.auditor.name);
        assertEq(_retrievedAuditSummary.summary.auditor.uri, _signedAuditSummary.summary.auditor.uri);
        assertEq(_retrievedAuditSummary.summary.auditor.authors, _signedAuditSummary.summary.auditor.authors);
        assertEq(_retrievedAuditSummary.summary.issuedAt, _signedAuditSummary.summary.issuedAt);
        assertEq(_retrievedAuditSummary.summary.ercs, _signedAuditSummary.summary.ercs);
        assertEq(_retrievedAuditSummary.summary.bytecodeHash, _signedAuditSummary.summary.bytecodeHash);
        assertEq(_retrievedAuditSummary.summary.auditHash, _signedAuditSummary.summary.auditHash);
        assertEq(_retrievedAuditSummary.summary.auditUri, _signedAuditSummary.summary.auditUri);
        assertEq(_retrievedAuditSummary.signedAt, _signedAuditSummary.signedAt);
        assertEq(
            uint8(_retrievedAuditSummary.auditorSignature.signatureType),
            uint8(_signedAuditSummary.auditorSignature.signatureType)
        );
        assertEq(_retrievedAuditSummary.auditorSignature.data, _signedAuditSummary.auditorSignature.data);
    }

    function test_PointsHookWithMetadata_name() external view {
        assertEq(hook.name(), "Counter");
    }

    function test_PointsHookWithMetadata_repositoryURI() external view {
        assertEq(hook.repositoryURI(), "Hook's repository URI");
    }

    function test_PointsHookWithMetadata_logoURI() external view {
        assertEq(hook.logoURI(), "Hook's logo URI");
    }

    function test_PointsHookWithMetadata_websiteURI() external view {
        assertEq(hook.websiteURI(), "Hook's website URI");
    }

    function test_PointsHookWithMetadata_description() external view {
        assertEq(hook.description(), "Counter hook with metadata which might be useful for external indexing services.");
    }

    function test_PointsHookWithMetadata_version() external view {
        assertEq(hook.version(), "1.0");
    }
}
