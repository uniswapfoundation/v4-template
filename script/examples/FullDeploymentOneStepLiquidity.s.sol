// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IUniswapV4Router04} from "hookmate/interfaces/router/IUniswapV4Router04.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {TokenApprover} from "../utils/TokenApprover.sol";
import {TokenUtils} from "../utils/TokenUtils.sol";
import {PoolInputs, PositionInputs, CurrencyPair} from "../types/Types.sol";
import {LoadDependencies} from "../actions/LoadDependencies.sol";
import {DeployToken} from "../actions/DeployToken.sol";
import {DeployHooks} from "../actions/DeployHooks.sol";
import {BootstrapPool} from "../actions/BootstrapPool.sol";
import {ExecuteSwap} from "../actions/ExecuteSwap.sol";

/// @dev Run e2e for create pool / add liquidity in one step
contract OneStepLiquidityScript is Script {
    /// Pool configuration
    PoolInputs public poolInputs = PoolInputs({
        lpFee: 5000, // 0.5%
        tickSpacing: 100,
        startingPrice: 2 ** 96 // sqrtPriceX96; floor(sqrt(1) * 2^96)
    });

    /// Position configuration
    PositionInputs public positionInputs = PositionInputs({
        token0Amount: 20 ether,
        token1Amount: 20 ether,
        // We're just creating a 50/50 position surrounding starting price
        tickLower: TickMath.getTickAtSqrtPrice(poolInputs.startingPrice) - 750 * poolInputs.tickSpacing,
        tickUpper: TickMath.getTickAtSqrtPrice(poolInputs.startingPrice) + 750 * poolInputs.tickSpacing,
        // Position slippage
        amount0Max: 20 ether + 1 wei,
        amount1Max: 20 ether + 1 wei,
        deadline: block.timestamp + 2500,
        hookData: new bytes(0)
    });

    /// Currency pair
    CurrencyPair public currencyPair;

    address deployer = vm.getWallets()[0];

    function run() public {
        vm.startBroadcast();

        /// -- 00 -- Load dependencies for network
        (IPermit2 permit2, IPoolManager poolManager, IPositionManager positionManager, IUniswapV4Router04 swapRouter) =
            LoadDependencies.run();
        // Label
        vm.label(address(permit2), "Permit2");
        vm.label(address(poolManager), "PoolManager");
        vm.label(address(positionManager), "PositionManager");
        vm.label(address(swapRouter), "SwapRouter");
        /// -- 01 -- Deploy tokens for a mock currency pair
        (IERC20 token0) = DeployToken.run("MockToken0", "MOCK0", 100 ether, deployer);
        (IERC20 token1) = DeployToken.run("MockToken1", "MOCK1", 100 ether, deployer);
        // Tokens must be numerically sorted, reassign values accordingly
        (token0, token1) = TokenUtils.sortTokens(token0, token1);
        currencyPair.currency0 = Currency.wrap(address(token0));
        currencyPair.currency1 = Currency.wrap(address(token1));
        // Label
        vm.label(address(token0), string.concat("token0/", token0.symbol()));
        vm.label(address(token1), string.concat("token1/", token1.symbol()));
        /// -- 02 -- Deploy hooks
        IHooks hooks = DeployHooks.run(poolManager, CREATE2_FACTORY);
        // Label
        vm.label(address(hooks), "HooksContract");
        /// -- 03a -- Create pool and add liquidity
        BootstrapPool.run(permit2, positionManager, currencyPair, hooks, poolInputs, positionInputs, deployer);
        /// -- 04 -- Perform swap
        // amountOutMin set to zero -- NOT for use in prod!
        ExecuteSwap.run(
            permit2,
            swapRouter,
            currencyPair,
            hooks,
            poolInputs,
            0.01 ether,
            0,
            block.timestamp + 2500,
            positionInputs.hookData,
            deployer
        );

        vm.stopBroadcast();
    }
}
