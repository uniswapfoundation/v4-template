// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {MarginAccount} from "../src/MarginAccount.sol";
import {InsuranceFund} from "../src/InsuranceFund.sol";
import {FundingOracle} from "../src/FundingOracle.sol";
import {PerpsRouter} from "../src/PerpsRouter.sol";
import {PositionManager} from "../src/PositionManagerV2.sol";
import {PositionFactory} from "../src/PositionFactory.sol";
import {PositionNFT} from "../src/PositionNFT.sol";
import {MarketManager} from "../src/MarketManager.sol";

contract DeployAllNewScript is Script {
    // Known addresses from previous deployments - UPDATE THESE FOR MODULAR SYSTEM
    address constant USDC_ADDRESS = 0x5FbDB2315678afecb367f032d93F642f64180aa3; // MockUSDC
    address constant POSITION_FACTORY_ADDRESS = 0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9; // Existing PositionFactory
    address constant POSITION_NFT_ADDRESS = 0x62691153379fe1DaD882a2CC5f739caA82f05aC8; // Existing PositionNFT
    address constant MARKET_MANAGER_ADDRESS = 0x8A791620dd6260079BF849Dc5567aDC3F2FdC318; // Existing MarketManager
    address constant PERPS_HOOK_ADDRESS = 0x1234567890123456789012345678901234567890; // Existing PerpsHook
    address constant POOL_MANAGER_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // Placeholder - would be real Uniswap PoolManager
    
    MarginAccount public marginAccount;
    InsuranceFund public insuranceFund;
    FundingOracle public fundingOracle;
    PerpsRouter public perpsRouter;
    
    function run() external {
        console.log("Deploying all new contracts for Perpetual Futures Protocol");
        console.log("Deployer address:", msg.sender);
        console.log("Using USDC at:", USDC_ADDRESS);
        console.log("Using existing PositionFactory at:", POSITION_FACTORY_ADDRESS);
        console.log("Using existing PositionNFT at:", POSITION_NFT_ADDRESS);
        console.log("Using existing MarketManager at:", MARKET_MANAGER_ADDRESS);
        console.log("Using existing PerpsHook at:", PERPS_HOOK_ADDRESS);
        
        vm.startBroadcast();
        
        // 1. Deploy MarginAccount
        console.log("\n1. Deploying MarginAccount...");
        marginAccount = new MarginAccount(USDC_ADDRESS);
        console.log("MarginAccount deployed to:", address(marginAccount));
        
        // 2. Deploy InsuranceFund
        console.log("\n2. Deploying InsuranceFund...");
        insuranceFund = new InsuranceFund(USDC_ADDRESS);
        console.log("InsuranceFund deployed to:", address(insuranceFund));
        
        // 3. Deploy FundingOracle
        console.log("\n3. Deploying FundingOracle...");
        // Use a placeholder address for Pyth - in production this would be the real Pyth contract
        address pythContract = address(0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF); // Placeholder
        fundingOracle = new FundingOracle(pythContract);
        console.log("FundingOracle deployed to:", address(fundingOracle));
        
        // 4. Deploy PerpsRouter
        console.log("\n4. Deploying PerpsRouter...");
        perpsRouter = new PerpsRouter(
            POSITION_FACTORY_ADDRESS,
            POSITION_NFT_ADDRESS,
            MARKET_MANAGER_ADDRESS,
            address(fundingOracle),
            POOL_MANAGER_ADDRESS,
            USDC_ADDRESS
        );
        console.log("PerpsRouter deployed to:", address(perpsRouter));
        
        // 5. Setup authorizations
        console.log("\n5. Setting up authorizations...");
        
        // MarginAccount authorizations
        marginAccount.addAuthorizedContract(address(perpsRouter));
        marginAccount.addAuthorizedContract(POSITION_FACTORY_ADDRESS);
        marginAccount.addAuthorizedContract(PERPS_HOOK_ADDRESS);
        console.log("MarginAccount authorizations set for Router, PositionFactory, and PerpsHook");
        
        // InsuranceFund authorizations
        insuranceFund.addAuthorizedContract(address(perpsRouter));
        insuranceFund.addAuthorizedContract(POSITION_FACTORY_ADDRESS);
        insuranceFund.addAuthorizedContract(PERPS_HOOK_ADDRESS);
        console.log("InsuranceFund authorizations set for Router, PositionFactory, and PerpsHook");
        
        // 6. Initialize insurance fund with initial deposit
        console.log("\n6. Initializing InsuranceFund with initial deposit...");
        // Note: This would require deployer to have USDC - for testing, we'll skip actual deposit
        // insuranceFund.deposit(50000e6); // $50,000 initial fund
        console.log("InsuranceFund ready for initial deposit");
        
        vm.stopBroadcast();
        
        // 7. Print deployment summary
        console.log("\n=====================================");
        console.log("DEPLOYMENT SUMMARY");
        console.log("=====================================");
        console.log("MarginAccount:    ", address(marginAccount));
        console.log("InsuranceFund:    ", address(insuranceFund));
        console.log("FundingOracle:    ", address(fundingOracle));
        console.log("PerpsRouter:      ", address(perpsRouter));
        console.log("=====================================");
        console.log("Existing Contracts:");
        console.log("MockUSDC:         ", USDC_ADDRESS);
        console.log("PositionFactory:  ", POSITION_FACTORY_ADDRESS);
        console.log("PositionNFT:      ", POSITION_NFT_ADDRESS);
        console.log("MarketManager:    ", MARKET_MANAGER_ADDRESS);
        console.log("PerpsHook:        ", PERPS_HOOK_ADDRESS);
        console.log("=====================================");
        
        console.log("\nNext steps:");
        console.log("1. Update PerpsHook to integrate with MarginAccount and InsuranceFund");
        console.log("2. Update PositionManager to integrate with MarginAccount and FundingOracle");
        console.log("3. Add market to FundingOracle for the ETH-USDC perp");
        console.log("4. Fund the InsuranceFund with initial USDC");
        console.log("5. Test full user flows through PerpsRouter");
    }
}
