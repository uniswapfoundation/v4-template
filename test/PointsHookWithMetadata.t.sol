// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {IHookMetadata} from "v4-periphery/src/interfaces/IHookMetadata.sol";
import {PointsHookWithMetadata} from "../src/PointsHookWithMetadata.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IEIP7512} from "v4-periphery/src/interfaces/IEIP7512.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";
import "forge-std/Test.sol";

contract PointsHookWithMetadataTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using StateLibrary for IPoolManager;

    event AuditSummaryRegistered(uint256 indexed auditId, bytes32 auditHash, string auditUri);

    PointsHookWithMetadata hook;
    int24 tickLower;
    int24 tickUpper;

    function setUp() external {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        deployAndApprovePosm(manager);

        address _flags = address(uint160(Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG) ^ (0x4444 << 144));
        bytes memory _constructorArgs = abi.encode(manager);

        deployCodeTo("PointsHookWithMetadata.sol:PointsHookWithMetadata", _constructorArgs, _flags);

        hook = PointsHookWithMetadata(_flags);
        key = PoolKey(Currency.wrap(address(0)), currency1, 3000, 60, IHooks(hook));

        manager.initialize(key, SQRT_PRICE_1_1);

        tickLower = TickMath.minUsableTick(key.tickSpacing);
        tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        deal(address(this), 200 ether);

        (uint256 _amount0, uint256 _amount1) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            uint128(100e18)
        );

        posm.mint(
            key,
            tickLower,
            tickUpper,
            100e18,
            _amount0 + 1,
            _amount1 + 1,
            address(this),
            block.timestamp,
            hook.getHookData(address(this))
        );
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

        PointsHookWithMetadata.SignedAuditSummary memory _retrievedAuditSummary = hook.auditSummaries(_auditId);

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
        assertEq(hook.name(), "PointsHookWithMetadata");
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
        assertEq(hook.description(), "Points hook with metadata which might be useful for external indexing services.");
    }

    function test_PointsHookWithMetadata_version() external view {
        assertEq(hook.version(), "1.0");
    }

    function test_PointsHookWithMetadata_Swap() external {
        uint256 _startingPoints = hook.pointsToken().balanceOf(address(this));
        bool _zeroForOne = true;
        int256 _amountSpecified = -1e18;

        swap(key, _zeroForOne, _amountSpecified, hook.getHookData(address(this)));

        uint256 _endingPoints = hook.pointsToken().balanceOf(address(this));

        assertEq(
            _endingPoints - _startingPoints,
            uint256(-_amountSpecified),
            "Points awarded for swap should be 1:1 with ETH"
        );
    }

    function test_PointsHookWithMetadata_AddLiquidity() external {
        uint256 _startingPoints = hook.pointsToken().balanceOf(address(this));
        uint128 _liquidityToAdd = 100e18;
        (uint256 _amount0, uint256 _amount1) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            _liquidityToAdd
        );

        posm.mint(
            key,
            tickLower,
            tickUpper,
            _liquidityToAdd,
            _amount0 + 1,
            _amount1 + 1,
            address(this),
            block.timestamp,
            hook.getHookData(address(this))
        );

        uint256 _endingPoints = hook.pointsToken().balanceOf(address(this));

        assertApproxEqAbs(
            _endingPoints - _startingPoints,
            uint256(_liquidityToAdd),
            10,
            "Points awarded for liquidity addition should be 1:1 with ETH"
        );
    }
}
