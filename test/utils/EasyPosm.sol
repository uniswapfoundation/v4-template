// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.21;

import {BalanceDelta, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {PositionConfig} from "v4-periphery/src/libraries/PositionConfig.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";

/// @title Easy Position Manager
/// @notice A library for abstracting Position Manager calldata
/// @dev Useable onchain, but expensive because of encoding
library EasyPosm {
    using CurrencyLibrary for Currency;
    using SafeCast for uint256;
    using SafeCast for int256;

    function mint(
        IPositionManager posm,
        PositionConfig memory config,
        uint256 liquidity,
        uint256 amount0Max,
        uint256 amount1Max,
        address recipient,
        uint256 deadline,
        bytes memory hookData
    ) internal returns (uint256 tokenId, BalanceDelta delta) {
        Currency currency0 = config.poolKey.currency0;
        Currency currency1 = config.poolKey.currency1;

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(config, liquidity, amount0Max, amount1Max, recipient, hookData);
        params[1] = abi.encode(currency0, currency1);

        uint256 balance0Before = currency0.balanceOf(address(this));
        uint256 balance1Before = currency1.balanceOf(address(this));

        // Mint Liquidity
        tokenId = posm.nextTokenId();
        posm.modifyLiquidities(
            abi.encode(abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR)), params), deadline
        );

        delta = toBalanceDelta(
            -(balance0Before - currency0.balanceOf(address(this))).toInt128(),
            -(balance1Before - currency1.balanceOf(address(this))).toInt128()
        );
    }

    function increaseLiquidity(
        IPositionManager posm,
        uint256 tokenId,
        PositionConfig memory config,
        uint256 liquidityToAdd,
        uint256 amount0Max,
        uint256 amount1Max,
        uint256 deadline,
        bytes memory hookData
    ) internal returns (BalanceDelta delta) {
        Currency currency0 = config.poolKey.currency0;
        Currency currency1 = config.poolKey.currency1;

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(tokenId, config, liquidityToAdd, amount0Max, amount1Max, hookData);
        params[1] = abi.encode(currency0);
        params[2] = abi.encode(currency1);

        uint256 balance0Before = currency0.balanceOf(address(this));
        uint256 balance1Before = currency1.balanceOf(address(this));

        posm.modifyLiquidities(
            abi.encode(
                abi.encodePacked(
                    uint8(Actions.INCREASE_LIQUIDITY), uint8(Actions.CLOSE_CURRENCY), uint8(Actions.CLOSE_CURRENCY)
                ),
                params
            ),
            deadline
        );

        delta = toBalanceDelta(
            (currency0.balanceOf(address(this)).toInt256() - balance0Before.toInt256()).toInt128(),
            (currency1.balanceOf(address(this)).toInt256() - balance1Before.toInt256()).toInt128()
        );
    }

    function decreaseLiquidity(
        IPositionManager posm,
        uint256 tokenId,
        PositionConfig memory config,
        uint256 liquidityToRemove,
        uint256 amount0Min,
        uint256 amount1Min,
        address recipient,
        uint256 deadline,
        bytes memory hookData
    ) internal returns (BalanceDelta delta) {
        Currency currency0 = config.poolKey.currency0;
        Currency currency1 = config.poolKey.currency1;

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(tokenId, config, liquidityToRemove, amount0Min, amount1Min, hookData);
        params[1] = abi.encode(currency0, currency1, recipient);

        uint256 balance0Before = currency0.balanceOf(address(this));
        uint256 balance1Before = currency1.balanceOf(address(this));

        posm.modifyLiquidities(
            abi.encode(abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR)), params), deadline
        );

        delta = toBalanceDelta(
            (currency0.balanceOf(address(this)) - balance0Before).toInt128(),
            (currency1.balanceOf(address(this)) - balance1Before).toInt128()
        );
    }

    function collect(
        IPositionManager posm,
        uint256 tokenId,
        PositionConfig memory config,
        uint256 amount0Min,
        uint256 amount1Min,
        address recipient,
        uint256 deadline,
        bytes memory hookData
    ) internal returns (BalanceDelta delta) {
        Currency currency0 = config.poolKey.currency0;
        Currency currency1 = config.poolKey.currency1;

        bytes[] memory params = new bytes[](2);
        // collecting fees is achieved by decreasing liquidity with 0 liquidity removed
        params[0] = abi.encode(tokenId, config, 0, amount0Min, amount1Min, hookData);
        params[1] = abi.encode(currency0, currency1, recipient);

        uint256 balance0Before = currency0.balanceOf(recipient);
        uint256 balance1Before = currency1.balanceOf(recipient);

        posm.modifyLiquidities(
            abi.encode(abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR)), params), deadline
        );

        delta = toBalanceDelta(
            (currency0.balanceOf(recipient) - balance0Before).toInt128(),
            (currency1.balanceOf(recipient) - balance1Before).toInt128()
        );
    }

    function burn(
        IPositionManager posm,
        uint256 tokenId,
        PositionConfig memory config,
        uint256 amount0Min,
        uint256 amount1Min,
        address recipient,
        uint256 deadline,
        bytes memory hookData
    ) internal returns (BalanceDelta delta) {
        Currency currency0 = config.poolKey.currency0;
        Currency currency1 = config.poolKey.currency1;

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(tokenId, config, 0, amount0Min, amount1Min, hookData);
        params[1] = abi.encode(currency0, currency1, recipient);

        uint256 balance0Before = currency0.balanceOf(recipient);
        uint256 balance1Before = currency1.balanceOf(recipient);

        posm.modifyLiquidities(
            abi.encode(abi.encodePacked(uint8(Actions.BURN_POSITION), uint8(Actions.TAKE_PAIR)), params), deadline
        );

        delta = toBalanceDelta(
            (currency0.balanceOf(recipient) - balance0Before).toInt128(),
            (currency1.balanceOf(recipient) - balance1Before).toInt128()
        );
    }
}
