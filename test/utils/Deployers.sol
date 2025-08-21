// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";

import {IUniswapV4Router04} from "hookmate/interfaces/router/IUniswapV4Router04.sol";
import {AddressConstants} from "hookmate/constants/AddressConstants.sol";

import {Permit2Deployer} from "hookmate/artifacts/Permit2.sol";
import {V4PoolManagerDeployer} from "hookmate/artifacts/V4PoolManager.sol";
import {V4PositionManagerDeployer} from "hookmate/artifacts/V4PositionManager.sol";
import {V4RouterDeployer} from "hookmate/artifacts/V4Router.sol";

/**
 * Base Deployer Contract for Hook Testing
 *
 * Automatically does the following:
 * 1. Setup deployments for Permit2, PoolManager, PositionManager and V4SwapRouter.
 * 2. Check if chainId is 31337, is so, deploys local instances.
 * 3. If not, uses existing canonical deployments on the selected network.
 * 4. Provides utility functions to deploy tokens and currency pairs.
 *
 * This contract can be used for both local testing and fork testing.
 */
contract Deployers is Test {
    IPermit2 permit2;
    IPoolManager poolManager;
    IPositionManager positionManager;
    IUniswapV4Router04 swapRouter;

    function deployToken() internal returns (MockERC20 token) {
        token = new MockERC20("Test Token", "TEST", 18);
        token.mint(address(this), 10_000_000 ether);

        token.approve(address(permit2), type(uint256).max);
        token.approve(address(swapRouter), type(uint256).max);

        permit2.approve(address(token), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(token), address(poolManager), type(uint160).max, type(uint48).max);
    }

    function deployCurrencyPair() internal returns (Currency currency0, Currency currency1) {
        MockERC20 token0 = deployToken();
        MockERC20 token1 = deployToken();

        if (token0 > token1) {
            (token0, token1) = (token1, token0);
        }

        currency0 = Currency.wrap(address(token0));
        currency1 = Currency.wrap(address(token1));

        vm.label(address(token0), "Currency0");
        vm.label(address(token1), "Currency1");
    }

    function deployPermit2() internal {
        address permit2Address = AddressConstants.getPermit2Address();

        if (permit2Address.code.length > 0) {
            // Permit2 is already deployed, no need to etch it.
        } else {
            address tempDeployAddress = address(Permit2Deployer.deploy());

            vm.etch(permit2Address, tempDeployAddress.code);
        }

        permit2 = IPermit2(permit2Address);
        vm.label(permit2Address, "Permit2");
    }

    function deployPoolManager() internal {
        if (block.chainid == 31337) {
            poolManager = IPoolManager(address(V4PoolManagerDeployer.deploy(address(0x4444))));
        } else {
            poolManager = IPoolManager(AddressConstants.getPoolManagerAddress(block.chainid));
        }

        vm.label(address(poolManager), "V4PoolManager");
    }

    function deployPositionManager() internal {
        if (block.chainid == 31337) {
            positionManager = IPositionManager(
                address(
                    V4PositionManagerDeployer.deploy(
                        address(poolManager), address(permit2), 300_000, address(0), address(0)
                    )
                )
            );
        } else {
            positionManager = IPositionManager(AddressConstants.getPositionManagerAddress(block.chainid));
        }

        vm.label(address(positionManager), "V4PositionManager");
    }

    function deployRouter() internal {
        if (block.chainid == 31337) {
            swapRouter = IUniswapV4Router04(payable(V4RouterDeployer.deploy(address(poolManager), address(permit2))));
        } else {
            swapRouter = IUniswapV4Router04(payable(AddressConstants.getV4SwapRouterAddress(block.chainid)));
        }

        vm.label(address(swapRouter), "V4SwapRouter");
    }

    function deployArtifacts() internal {
        // Order matters.
        deployPermit2();
        deployPoolManager();
        deployPositionManager();
        deployRouter();
    }
}
