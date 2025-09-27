// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {PoolManager} from "v4-core/src/PoolManager.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolDonateTest} from "v4-core/src/test/PoolDonateTest.sol";
import {PoolTakeTest} from "v4-core/src/test/PoolTakeTest.sol";
import {PoolClaimsTest} from "v4-core/src/test/PoolClaimsTest.sol";

import {MockUSDC} from "../test/utils/mocks/MockUSDC.sol";
import {MockVETH} from "../test/utils/mocks/MockVETH.sol";

import {PerpsHook} from "../src/PerpsHook.sol";
import {PositionManager} from "../src/PositionManagerV2.sol";
import {PositionFactory} from "../src/PositionFactory.sol";
import {PositionNFT} from "../src/PositionNFT.sol";
import {MarketManager} from "../src/MarketManager.sol";
import {MarginAccount} from "../src/MarginAccount.sol";
import {FundingOracle} from "../src/FundingOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AnvilScript is Script {
    // Addresses for Anvil's default accounts
    address constant DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address constant USER1 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address constant USER2 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;

    PoolManager poolManager;
    PoolSwapTest swapRouter;
    PoolModifyLiquidityTest modifyLiquidityRouter;
    PoolDonateTest donateRouter;
    PoolTakeTest takeRouter;
    PoolClaimsTest claimsRouter;

    MockUSDC token0;
    MockVETH token1;

    PerpsHook perpsHook;
    PositionManager positionManager;
    PositionFactory positionFactory;
    PositionNFT positionNFT;
    MarketManager marketManager;

    function run() external {
        vm.startBroadcast(DEPLOYER);

        // Deploy the PoolManager
        poolManager = new PoolManager(DEPLOYER);
        console.log("PoolManager deployed at:", address(poolManager));

        // Deploy test routers for interacting with the PoolManager
        swapRouter = new PoolSwapTest(poolManager);
        console.log("PoolSwapTest deployed at:", address(swapRouter));

        modifyLiquidityRouter = new PoolModifyLiquidityTest(poolManager);
        console.log("PoolModifyLiquidityTest deployed at:", address(modifyLiquidityRouter));

        donateRouter = new PoolDonateTest(poolManager);
        console.log("PoolDonateTest deployed at:", address(donateRouter));

        takeRouter = new PoolTakeTest(poolManager);
        console.log("PoolTakeTest deployed at:", address(takeRouter));

        claimsRouter = new PoolClaimsTest(poolManager);
        console.log("PoolClaimsTest deployed at:", address(claimsRouter));

        // Deploy test tokens
        token0 = new MockUSDC();
        token1 = new MockVETH();

        console.log("MockUSDC deployed at:", address(token0));
        console.log("MockETH deployed at:", address(token1));

        // Mint tokens to test accounts
        token0.mint(DEPLOYER, 1000000 * 10**6); // 1M USDC
        token0.mint(USER1, 100000 * 10**6);     // 100K USDC
        token0.mint(USER2, 100000 * 10**6);     // 100K USDC

        token1.mint(DEPLOYER, 1000 * 10**18);   // 1000 ETH
        token1.mint(USER1, 100 * 10**18);       // 100 ETH
        token1.mint(USER2, 100 * 10**18);       // 100 ETH

        console.log("Tokens minted to test accounts");

        // Deploy modular PositionManager system
        positionFactory = new PositionFactory(address(token0), address(0)); // No MarginAccount for simple demo
        console.log("PositionFactory deployed at:", address(positionFactory));
        
        positionNFT = new PositionNFT();
        console.log("PositionNFT deployed at:", address(positionNFT));
        
        marketManager = new MarketManager();
        console.log("MarketManager deployed at:", address(marketManager));
        
        positionManager = new PositionManager(
            address(positionFactory),
            address(positionNFT),
            address(marketManager)
        );
        console.log("PositionManager deployed at:", address(positionManager));
        
        // Set up component relationships
        positionFactory.setPositionNFT(address(positionNFT));
        positionNFT.setFactory(address(positionFactory));

        // Deploy our PerpsHook
        perpsHook = new PerpsHook(
            poolManager, 
            positionManager,  // PositionManager instance 
            positionFactory,  // PositionFactory instance
            MarginAccount(address(0)), 
            FundingOracle(payable(address(0))),
            IERC20(address(token0)) // USDC token
        );
        console.log("PerpsHook deployed at:", address(perpsHook));

        // Fund the PerpsHook with some tokens for testing
        token0.mint(address(perpsHook), 100000 * 10**6); // 100K USDC for payouts

        console.log("=== Deployment Summary ===");
        console.log("PoolManager:", address(poolManager));
        console.log("SwapRouter:", address(swapRouter));
        console.log("ModifyLiquidityRouter:", address(modifyLiquidityRouter));
        console.log("DonateRouter:", address(donateRouter));
        console.log("TakeRouter:", address(takeRouter));
        console.log("ClaimsRouter:", address(claimsRouter));
        console.log("USDC Token:", address(token0));
        console.log("ETH Token:", address(token1));
        console.log("PositionManager:", address(positionManager));
        console.log("PerpsHook:", address(perpsHook));
        console.log("");
        console.log("Test Accounts:");
        console.log("Deployer:", DEPLOYER);
        console.log("User1:", USER1);
        console.log("User2:", USER2);

        vm.stopBroadcast();
    }
}
