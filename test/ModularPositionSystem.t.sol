// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {PositionLib} from "../src/libraries/PositionLib.sol";
import {PositionFactory} from "../src/PositionFactory.sol";
import {PositionNFT} from "../src/PositionNFT.sol";
import {MarketManager} from "../src/MarketManager.sol";
import {PositionManager} from "../src/PositionManagerV2.sol";
import {MarginAccount} from "../src/MarginAccount.sol";
import {MockUSDC} from "../test/utils/mocks/MockUSDC.sol";

contract ModularPositionSystemTest is Test {
    // Contract instances
    MockUSDC usdc;
    MarginAccount marginAccount;
    PositionFactory positionFactory;
    PositionNFT positionNFT;
    MarketManager marketManager;
    PositionManager positionManager;

    // Test users
    address user1 = address(0x1);
    address user2 = address(0x2);

    // Test constants
    bytes32 constant ETH_USDC_MARKET = keccak256("ETH/USDC");
    uint256 constant TEST_MARGIN = 1000e6; // 1000 USDC
    int256 constant TEST_SIZE = 1e18; // 1 ETH
    uint256 constant TEST_PRICE = 2000e18; // $2000

    function setUp() public {
        // Deploy all contracts with this test contract as owner
        usdc = new MockUSDC();
        marginAccount = new MarginAccount(address(usdc));
        positionFactory = new PositionFactory(address(usdc), address(marginAccount));
        positionNFT = new PositionNFT();
        marketManager = new MarketManager();
        positionManager = new PositionManager(
            address(positionFactory),
            address(positionNFT),
            address(marketManager)
        );

        // Configure relationships - this contract is the owner
        positionNFT.setFactory(address(positionFactory));
        positionFactory.setPositionNFT(address(positionNFT));
        marginAccount.addAuthorizedContract(address(positionFactory));

        // Setup test market - call as owner using explicit address(this)
        marketManager.addMarket(
            ETH_USDC_MARKET,
            address(0x123), // Mock ETH token
            address(usdc),
            address(0x456)  // Mock pool
        );
        
        positionFactory.addMarket(
            ETH_USDC_MARKET,
            address(0x123), // Mock ETH token
            address(usdc),
            address(0x456)  // Mock pool
        );

        // Setup test users with USDC
        usdc.mint(user1, 10000e6);
        usdc.mint(user2, 10000e6);
        
        vm.prank(user1);
        usdc.approve(address(marginAccount), type(uint256).max);
        vm.prank(user1);
        marginAccount.deposit(5000e6); // Deposit 5000 USDC for user1
        
        vm.prank(user2);
        usdc.approve(address(marginAccount), type(uint256).max);
        vm.prank(user2);
        marginAccount.deposit(5000e6); // Deposit 5000 USDC for user2
    }

    function test_ModularSystemBasicFlow() public {
        console.log("=== Testing Modular Position System ===");

        // Test opening a position
        vm.prank(user1);
        uint256 tokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            TEST_SIZE,
            TEST_PRICE,
            TEST_MARGIN
        );

        console.log("Position opened with tokenId:", tokenId);

        // Verify NFT was minted
        assertEq(positionNFT.ownerOf(tokenId), user1);
        assertEq(positionNFT.totalSupply(), 1);

        // Verify position data
        PositionLib.Position memory position = positionManager.getPosition(tokenId);
        assertEq(position.owner, user1);
        assertEq(position.margin, TEST_MARGIN);
        assertEq(position.sizeBase, TEST_SIZE);
        assertEq(position.entryPrice, TEST_PRICE);

        // Test updating position
        vm.prank(user1);
        bool success = positionManager.updatePosition(tokenId, TEST_SIZE / 2, TEST_MARGIN / 2);
        assertTrue(success);

        // Verify update
        position = positionManager.getPosition(tokenId);
        assertEq(position.sizeBase, TEST_SIZE / 2);
        assertEq(position.margin, TEST_MARGIN / 2);

        // Test closing position
        vm.prank(user1);
        positionManager.closePosition(tokenId, TEST_PRICE + 100e18); // Close at profit

        // Verify position was deleted and NFT burned
        vm.expectRevert();
        positionNFT.ownerOf(tokenId);
        
        assertEq(positionNFT.totalSupply(), 0);

        console.log("All tests passed!");
    }

    function test_ContractSizes() public view {
        console.log("=== Contract Sizes ===");
        
        uint256 factorySize = address(positionFactory).code.length;
        uint256 nftSize = address(positionNFT).code.length;
        uint256 marketManagerSize = address(marketManager).code.length;
        uint256 orchestratorSize = address(positionManager).code.length;
        
        console.log("PositionFactory:", factorySize, "bytes");
        console.log("PositionNFT:", nftSize, "bytes");
        console.log("MarketManager:", marketManagerSize, "bytes");
        console.log("PositionManager:", orchestratorSize, "bytes");
        
        // All should be under EIP-170 limit
        assertLt(factorySize, 24576, "PositionFactory exceeds size limit");
        assertLt(nftSize, 24576, "PositionNFT exceeds size limit");
        assertLt(marketManagerSize, 24576, "MarketManager exceeds size limit");
        assertLt(orchestratorSize, 24576, "PositionManager exceeds size limit");
        
        console.log("All contracts are under EIP-170 limit!");
    }

    function test_BackwardCompatibility() public {
        console.log("=== Testing Backward Compatibility ===");

        // Test that the orchestrator maintains the same interface
        vm.prank(user1);
        uint256 tokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            TEST_SIZE,
            TEST_PRICE,
            TEST_MARGIN
        );

        // Test ERC721 compatibility functions
        assertEq(positionManager.ownerOf(tokenId), user1);
        assertEq(positionManager.balanceOf(user1), 1);
        assertEq(positionManager.totalSupply(), 1);
        assertEq(positionManager.tokenByIndex(0), tokenId);
        assertEq(positionManager.tokenOfOwnerByIndex(user1, 0), tokenId);

        // Test position query functions
        PositionLib.Position memory position = positionManager.getPosition(tokenId);
        assertEq(position.owner, user1);

        // Test market query functions
        PositionLib.Market memory market = positionManager.getMarket(ETH_USDC_MARKET);
        assertTrue(market.isActive);

        uint256[] memory userPositions = positionManager.getUserPositions(user1);
        assertEq(userPositions.length, 1);
        assertEq(userPositions[0], tokenId);

        console.log("Backward compatibility maintained!");
    }
}
