// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";

import {Permit2Deployer} from "@uniswap/briefcase/deployers/permit2/Permit2Deployer.sol";
import {PoolManagerDeployer} from "@uniswap/briefcase/deployers/v4-core/PoolManagerDeployer.sol";
import {PositionManagerDeployer} from "@uniswap/briefcase/deployers/v4-periphery/PositionManagerDeployer.sol";

/**
 * TODO:
 * [x] Setup deployments for Permit2, PoolManager, and PositionManager.
 * [ ] Check if chainId is 31337, is so, etch them all.
 * [ ] If not, use the existing deployment addresses for the specified chain.
 */
contract Deployers is Test {
    function deployToken() internal returns (MockERC20 token) {
        token = new MockERC20("Test Token", "TEST", 18);
        token.mint(address(this), type(uint256).max);
    }

    function deployCurrencyPair() internal returns (Currency currency0, Currency currency1) {
        MockERC20 token0 = deployToken();
        MockERC20 token1 = deployToken();

        currency0 = Currency.wrap(address(token0));
        currency1 = Currency.wrap(address(token1));

        vm.label(address(token0), "Currency0");
        vm.label(address(token1), "Currency1");
    }

    function deployPermit2() internal returns (IAllowanceTransfer) {
        address permit2Address = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        vm.label(permit2Address, "Permit2");

        vm.etch(permit2Address, Permit2Deployer.initcode());

        return IAllowanceTransfer(permit2Address);
    }

    function deployPoolManager() internal returns (IPoolManager) {
        address poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
        vm.label(poolManager, "V4:PoolManager");

        bytes memory initcode_ = abi.encodePacked(PoolManagerDeployer.initcode(), abi.encode(address(0)));
        vm.etch(poolManager, initcode_);

        return IPoolManager(poolManager);
    }

    function deployPositionManager(IPoolManager poolManager, IAllowanceTransfer permit2)
        internal
        returns (IPositionManager)
    {
        address positionManager = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
        vm.label(positionManager, "V4:PositionManager");

        bytes memory initcode_ = abi.encodePacked(
            PositionManagerDeployer.initcode(),
            abi.encode(address(poolManager), address(permit2), 300_000, address(0), address(0))
        );

        vm.etch(positionManager, initcode_);

        return IPositionManager(positionManager);
    }

    function deployAll()
        internal
        returns (IAllowanceTransfer permit2, IPoolManager poolManager, IPositionManager positionManager)
    {
        permit2 = deployPermit2();
        poolManager = deployPoolManager();
        positionManager = deployPositionManager(poolManager, permit2);
    }
}
