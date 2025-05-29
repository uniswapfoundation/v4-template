// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

import {IUniswapV4Router04} from "hookmate/interfaces/router/IUniswapV4Router04.sol";
import {Constants} from "hookmate/constants/Constants.sol";

/// @notice Shared configuration between scripts
contract BaseScript is Script {
    IAllowanceTransfer immutable permit2 = IAllowanceTransfer(address(0x000000000022D473030F116dDEE9F6B43aC78BA3));
    IPoolManager immutable poolManager;
    PositionManager immutable positionManager;
    IUniswapV4Router04 immutable swapRouter;

    /////////////////////////////////////
    // --- Configure These ---
    /////////////////////////////////////
    IERC20 internal constant token0 = IERC20(address(0x0165878A594ca255338adfa4d48449f69242Eb8F));
    IERC20 internal constant token1 = IERC20(address(0xa513E6E4b8f2a923D98304ec87F64353C4D5C853));
    IHooks constant hookContract = IHooks(address(0x0));

    constructor() {
        poolManager = IPoolManager(Constants.getPoolManagerAddressByChainId(block.chainid));
        positionManager = PositionManager(payable(Constants.getPositionManagerAddressByChainId(block.chainid)));
        swapRouter = IUniswapV4Router04(payable(Constants.getV4SwapRouterAddress()));
    }

    function setUp() public virtual {}

    function getCurrencies() public pure returns (Currency, Currency) {
        require(address(token0) != address(token1));

        if (token0 < token1) {
            return (Currency.wrap(address(token0)), Currency.wrap(address(token1)));
        } else {
            return (Currency.wrap(address(token1)), Currency.wrap(address(token0)));
        }
    }

    function getDeployer() public returns (address) {
        address[] memory wallets = vm.getWallets();
        require(wallets.length > 0, "No wallets found");

        return wallets[0];
    }
}
