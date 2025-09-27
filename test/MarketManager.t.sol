// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/MarketManager.sol";
import "../src/libraries/PositionLib.sol";

contract MarketManagerTest is Test {
    MarketManager public marketManager;
    address public owner;
    address public nonOwner;
    address public baseAsset;
    address public quoteAsset; 
    address public poolAddress;
    bytes32 public marketId;

    event MarketAdded(bytes32 indexed marketId, address baseAsset, address quoteAsset, address poolAddress);
    event MarketStatusUpdated(bytes32 indexed marketId, bool isActive);
    event FundingIndexUpdated(bytes32 indexed marketId, uint256 newIndex);

    function setUp() public {
        owner = address(this);
        nonOwner = address(0x123);
        baseAsset = address(0x456);
        quoteAsset = address(0x789);
        poolAddress = address(0xabc);
        marketId = keccak256("ETH-USD");
        
        marketManager = new MarketManager();
    }

    function test_deployment() public view {
        assertEq(marketManager.owner(), owner);
    }

    function test_addMarket_success() public {
        vm.expectEmit(true, false, false, true);
        emit MarketAdded(marketId, baseAsset, quoteAsset, poolAddress);
        
        marketManager.addMarket(marketId, baseAsset, quoteAsset, poolAddress, 3000);
        
        PositionLib.Market memory market = marketManager.getMarket(marketId);
        assertEq(market.baseAsset, baseAsset);
        assertEq(market.quoteAsset, quoteAsset);
        assertEq(market.poolAddress, poolAddress);
        assertEq(market.lastFundingUpdate, block.timestamp);
        assertTrue(market.isActive);
        assertEq(market.fundingIndex, 1e18);
    }

    function test_addMarket_revert_market_exists() public {
        marketManager.addMarket(marketId, baseAsset, quoteAsset, poolAddress, 3000);
        
        vm.expectRevert("Market exists");
        marketManager.addMarket(marketId, baseAsset, quoteAsset, poolAddress, 3000);
    }

    function test_addMarket_revert_non_owner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        marketManager.addMarket(marketId, baseAsset, quoteAsset, poolAddress, 3000);
    }

    function test_setMarketStatus_success() public {
        marketManager.addMarket(marketId, baseAsset, quoteAsset, poolAddress, 3000);
        
        vm.expectEmit(true, false, false, true);
        emit MarketStatusUpdated(marketId, false);
        
        marketManager.updateMarketStatus(marketId, false);
        
        assertFalse(marketManager.isMarketActive(marketId));
    }

    function test_setMarketStatus_revert_market_not_found() public {
        vm.expectRevert("Market not found");
        marketManager.updateMarketStatus(marketId, false);
    }

    function test_setMarketStatus_revert_non_owner() public {
        marketManager.addMarket(marketId, baseAsset, quoteAsset, poolAddress, 3000);
        
        vm.prank(nonOwner);
        vm.expectRevert();
        marketManager.updateMarketStatus(marketId, false);
    }

    function test_updateFundingIndex_success() public {
        marketManager.addMarket(marketId, baseAsset, quoteAsset, poolAddress, 3000);
        uint256 newIndex = 1.5e18;
        
        vm.expectEmit(true, false, false, true);
        emit FundingIndexUpdated(marketId, newIndex);
        
        marketManager.updateFundingIndex(marketId, newIndex);
        
        assertEq(marketManager.getFundingIndex(marketId), newIndex);
    }

    function test_updateFundingIndex_revert_market_not_found() public {
        vm.expectRevert("Market not found");
        marketManager.updateFundingIndex(marketId, 1.5e18);
    }

    function test_updateFundingIndex_revert_non_owner() public {
        marketManager.addMarket(marketId, baseAsset, quoteAsset, poolAddress, 3000);
        
        vm.prank(nonOwner);
        vm.expectRevert();
        marketManager.updateFundingIndex(marketId, 1.5e18);
    }

    function test_getMarket_success() public {
        marketManager.addMarket(marketId, baseAsset, quoteAsset, poolAddress, 3000);
        
        PositionLib.Market memory market = marketManager.getMarket(marketId);
        assertEq(market.baseAsset, baseAsset);
        assertEq(market.quoteAsset, quoteAsset);
        assertEq(market.poolAddress, poolAddress);
        assertTrue(market.isActive);
        assertEq(market.fundingIndex, 1e18);
    }

    function test_getMarket_nonexistent() public view {
        PositionLib.Market memory market = marketManager.getMarket(marketId);
        assertEq(market.baseAsset, address(0));
        assertEq(market.quoteAsset, address(0));
        assertEq(market.poolAddress, address(0));
        assertFalse(market.isActive);
        assertEq(market.fundingIndex, 0);
    }

    function test_isMarketActive_true() public {
        marketManager.addMarket(marketId, baseAsset, quoteAsset, poolAddress, 3000);
        assertTrue(marketManager.isMarketActive(marketId));
    }

    function test_isMarketActive_false() public {
        marketManager.addMarket(marketId, baseAsset, quoteAsset, poolAddress, 3000);
        marketManager.updateMarketStatus(marketId, false);
        assertFalse(marketManager.isMarketActive(marketId));
    }

    function test_isMarketActive_nonexistent() public view {
        assertFalse(marketManager.isMarketActive(marketId));
    }

    function test_getFundingIndex_success() public {
        marketManager.addMarket(marketId, baseAsset, quoteAsset, poolAddress);
        assertEq(marketManager.getFundingIndex(marketId), 1e18);
        
        uint256 newIndex = 1.2e18;
        marketManager.updateFundingIndex(marketId, newIndex);
        assertEq(marketManager.getFundingIndex(marketId), newIndex);
    }

    function test_getFundingIndex_nonexistent() public view {
        assertEq(marketManager.getFundingIndex(marketId), 0);
    }

    function test_addPositionToMarket_success() public {
        marketManager.addMarket(marketId, baseAsset, quoteAsset, poolAddress);
        
        uint256 tokenId1 = 1;
        uint256 tokenId2 = 2;
        
        marketManager.addPositionToMarket(marketId, tokenId1);
        marketManager.addPositionToMarket(marketId, tokenId2);
        
        uint256[] memory positions = marketManager.getMarketPositions(marketId);
        assertEq(positions.length, 2);
        assertEq(positions[0], tokenId1);
        assertEq(positions[1], tokenId2);
    }

    function test_removePositionFromMarket_success() public {
        marketManager.addMarket(marketId, baseAsset, quoteAsset, poolAddress);
        
        uint256 tokenId1 = 1;
        uint256 tokenId2 = 2;
        uint256 tokenId3 = 3;
        
        marketManager.addPositionToMarket(marketId, tokenId1);
        marketManager.addPositionToMarket(marketId, tokenId2);
        marketManager.addPositionToMarket(marketId, tokenId3);
        
        // Remove middle position
        marketManager.removePositionFromMarket(marketId, tokenId2);
        
        uint256[] memory positions = marketManager.getMarketPositions(marketId);
        assertEq(positions.length, 2);
        assertEq(positions[0], tokenId1);
        assertEq(positions[1], tokenId3);
    }

    function test_removePositionFromMarket_first_position() public {
        marketManager.addMarket(marketId, baseAsset, quoteAsset, poolAddress);
        
        uint256 tokenId1 = 1;
        uint256 tokenId2 = 2;
        
        marketManager.addPositionToMarket(marketId, tokenId1);
        marketManager.addPositionToMarket(marketId, tokenId2);
        
        // Remove first position
        marketManager.removePositionFromMarket(marketId, tokenId1);
        
        uint256[] memory positions = marketManager.getMarketPositions(marketId);
        assertEq(positions.length, 1);
        assertEq(positions[0], tokenId2);
    }

    function test_removePositionFromMarket_last_position() public {
        marketManager.addMarket(marketId, baseAsset, quoteAsset, poolAddress);
        
        uint256 tokenId1 = 1;
        uint256 tokenId2 = 2;
        
        marketManager.addPositionToMarket(marketId, tokenId1);
        marketManager.addPositionToMarket(marketId, tokenId2);
        
        // Remove last position
        marketManager.removePositionFromMarket(marketId, tokenId2);
        
        uint256[] memory positions = marketManager.getMarketPositions(marketId);
        assertEq(positions.length, 1);
        assertEq(positions[0], tokenId1);
    }

    function test_removePositionFromMarket_single_position() public {
        marketManager.addMarket(marketId, baseAsset, quoteAsset, poolAddress);
        
        uint256 tokenId1 = 1;
        
        marketManager.addPositionToMarket(marketId, tokenId1);
        marketManager.removePositionFromMarket(marketId, tokenId1);
        
        uint256[] memory positions = marketManager.getMarketPositions(marketId);
        assertEq(positions.length, 0);
    }

    function test_removePositionFromMarket_nonexistent_position() public {
        marketManager.addMarket(marketId, baseAsset, quoteAsset, poolAddress);
        
        uint256 tokenId1 = 1;
        uint256 tokenId2 = 2;
        uint256 nonExistentTokenId = 999;
        
        marketManager.addPositionToMarket(marketId, tokenId1);
        marketManager.addPositionToMarket(marketId, tokenId2);
        
        // Try to remove non-existent position (should not revert)
        marketManager.removePositionFromMarket(marketId, nonExistentTokenId);
        
        uint256[] memory positions = marketManager.getMarketPositions(marketId);
        assertEq(positions.length, 2);
        assertEq(positions[0], tokenId1);
        assertEq(positions[1], tokenId2);
    }

    function test_getMarketPositions_empty() public {
        marketManager.addMarket(marketId, baseAsset, quoteAsset, poolAddress);
        
        uint256[] memory positions = marketManager.getMarketPositions(marketId);
        assertEq(positions.length, 0);
    }

    function test_getMarketPositions_nonexistent_market() public view {
        uint256[] memory positions = marketManager.getMarketPositions(marketId);
        assertEq(positions.length, 0);
    }

    function testFuzz_addMarket(
        bytes32 _marketId,
        address _baseAsset,
        address _quoteAsset,
        address _poolAddress
    ) public {
        vm.assume(_baseAsset != address(0));
        vm.assume(_quoteAsset != address(0));
        vm.assume(_poolAddress != address(0));
        vm.assume(_baseAsset != _quoteAsset);
        
        marketManager.addMarket(_marketId, _baseAsset, _quoteAsset, _poolAddress);
        
        PositionLib.Market memory market = marketManager.getMarket(_marketId);
        assertEq(market.baseAsset, _baseAsset);
        assertEq(market.quoteAsset, _quoteAsset);
        assertEq(market.poolAddress, _poolAddress);
        assertTrue(market.isActive);
        assertEq(market.fundingIndex, 1e18);
    }

    function testFuzz_updateFundingIndex(uint256 newIndex) public {
        marketManager.addMarket(marketId, baseAsset, quoteAsset, poolAddress);
        
        marketManager.updateFundingIndex(marketId, newIndex);
        
        assertEq(marketManager.getFundingIndex(marketId), newIndex);
    }

    function testFuzz_position_management(uint256[] memory tokenIds) public {
        vm.assume(tokenIds.length <= 100); // Prevent excessive gas usage
        
        marketManager.addMarket(marketId, baseAsset, quoteAsset, poolAddress);
        
        // Add all positions
        for (uint256 i = 0; i < tokenIds.length; i++) {
            marketManager.addPositionToMarket(marketId, tokenIds[i]);
        }
        
        uint256[] memory positions = marketManager.getMarketPositions(marketId);
        assertEq(positions.length, tokenIds.length);
        
        // Remove all positions
        for (uint256 i = 0; i < tokenIds.length; i++) {
            marketManager.removePositionFromMarket(marketId, tokenIds[i]);
        }
        
        positions = marketManager.getMarketPositions(marketId);
        assertEq(positions.length, 0);
    }

    function test_multiple_markets() public {
        bytes32 marketId1 = keccak256("ETH-USD");
        bytes32 marketId2 = keccak256("BTC-USD");
        address baseAsset2 = address(0x111);
        address quoteAsset2 = address(0x222);
        address poolAddress2 = address(0x333);
        
        marketManager.addMarket(marketId1, baseAsset, quoteAsset, poolAddress);
        marketManager.addMarket(marketId2, baseAsset2, quoteAsset2, poolAddress2);
        
        // Test market 1
        PositionLib.Market memory market1 = marketManager.getMarket(marketId1);
        assertEq(market1.baseAsset, baseAsset);
        assertEq(market1.quoteAsset, quoteAsset);
        
        // Test market 2
        PositionLib.Market memory market2 = marketManager.getMarket(marketId2);
        assertEq(market2.baseAsset, baseAsset2);
        assertEq(market2.quoteAsset, quoteAsset2);
        
        // Test independent position management
        marketManager.addPositionToMarket(marketId1, 1);
        marketManager.addPositionToMarket(marketId2, 2);
        
        uint256[] memory positions1 = marketManager.getMarketPositions(marketId1);
        uint256[] memory positions2 = marketManager.getMarketPositions(marketId2);
        
        assertEq(positions1.length, 1);
        assertEq(positions2.length, 1);
        assertEq(positions1[0], 1);
        assertEq(positions2[0], 2);
    }

    function test_ownership_transfer() public {
        address newOwner = address(0x999);
        
        marketManager.transferOwnership(newOwner);
        
        assertEq(marketManager.owner(), newOwner);
        
        // Old owner should not be able to add markets
        vm.expectRevert();
        marketManager.addMarket(marketId, baseAsset, quoteAsset, poolAddress, 3000);
        
        // New owner should be able to add markets
        vm.prank(newOwner);
        marketManager.addMarket(marketId, baseAsset, quoteAsset, poolAddress, 3000);
        
        assertTrue(marketManager.isMarketActive(marketId));
    }

    function test_keyManager_addMarket_success() public {
        address keyManager = address(0x123);
        
        // Add key manager
        marketManager.addKeyManager(keyManager);
        assertTrue(marketManager.keyManagers(keyManager));
        
        // Key manager should be able to add market
        vm.prank(keyManager);
        marketManager.addMarket(marketId, baseAsset, quoteAsset, poolAddress, 3000);
        
        assertTrue(marketManager.isMarketActive(marketId));
    }

    function test_keyManager_updateMarketStatus_success() public {
        address keyManager = address(0x123);
        
        // Add market first
        marketManager.addMarket(marketId, baseAsset, quoteAsset, poolAddress, 3000);
        
        // Add key manager
        marketManager.addKeyManager(keyManager);
        
        // Key manager should be able to update market status
        vm.prank(keyManager);
        marketManager.updateMarketStatus(marketId, false);
        
        assertFalse(marketManager.isMarketActive(marketId));
    }

    function test_keyManager_revert_non_owner_add() public {
        address keyManager = address(0x123);
        
        vm.prank(nonOwner);
        vm.expectRevert();
        marketManager.addKeyManager(keyManager);
    }

    function test_keyManager_remove_success() public {
        address keyManager = address(0x123);
        
        // Add key manager
        marketManager.addKeyManager(keyManager);
        assertTrue(marketManager.keyManagers(keyManager));
        
        // Remove key manager
        marketManager.removeKeyManager(keyManager);
        assertFalse(marketManager.keyManagers(keyManager));
        
        // Removed key manager should not be able to add markets
        vm.prank(keyManager);
        vm.expectRevert("Not authorized");
        marketManager.addMarket(marketId, baseAsset, quoteAsset, poolAddress, 3000);
    }
}
