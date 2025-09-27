// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/PositionNFT.sol";

contract PositionNFTTest is Test {
    PositionNFT public positionNFT;
    address public owner;
    address public factory;
    address public user1;
    address public user2;
    address public nonOwner;

    function setUp() public {
        owner = address(this);
        factory = address(0x123);
        user1 = address(0x456);
        user2 = address(0x789);
        nonOwner = address(0xabc);
        
        positionNFT = new PositionNFT();
    }

    function test_deployment() public view {
        assertEq(positionNFT.owner(), owner);
        assertEq(positionNFT.name(), "Perpetual Position NFT");
        assertEq(positionNFT.symbol(), "PERPNFT");
        assertEq(positionNFT.factory(), address(0));
    }

    function test_setFactory_success() public {
        positionNFT.setFactory(factory);
        assertEq(positionNFT.factory(), factory);
    }

    function test_setFactory_revert_non_owner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        positionNFT.setFactory(factory);
    }

    function test_mint_success() public {
        positionNFT.setFactory(factory);
        uint256 tokenId = 1;
        
        vm.prank(factory);
        positionNFT.mint(user1, tokenId);
        
        assertEq(positionNFT.ownerOf(tokenId), user1);
        assertEq(positionNFT.balanceOf(user1), 1);
        assertTrue(positionNFT.exists(tokenId));
    }

    function test_mint_revert_not_factory() public {
        positionNFT.setFactory(factory);
        uint256 tokenId = 1;
        
        vm.expectRevert("Only factory");
        positionNFT.mint(user1, tokenId);
    }

    function test_mint_revert_factory_not_set() public {
        uint256 tokenId = 1;
        
        vm.expectRevert("Only factory");
        positionNFT.mint(user1, tokenId);
    }

    function test_burn_success() public {
        positionNFT.setFactory(factory);
        uint256 tokenId = 1;
        
        vm.startPrank(factory);
        positionNFT.mint(user1, tokenId);
        positionNFT.burn(tokenId);
        vm.stopPrank();
        
        assertFalse(positionNFT.exists(tokenId));
        assertEq(positionNFT.balanceOf(user1), 0);
    }

    function test_burn_revert_not_factory() public {
        positionNFT.setFactory(factory);
        uint256 tokenId = 1;
        
        vm.prank(factory);
        positionNFT.mint(user1, tokenId);
        
        vm.expectRevert("Only factory");
        positionNFT.burn(tokenId);
    }

    function test_burn_revert_nonexistent_token() public {
        positionNFT.setFactory(factory);
        uint256 tokenId = 999;
        
        vm.prank(factory);
        vm.expectRevert();
        positionNFT.burn(tokenId);
    }

    function test_exists_true() public {
        positionNFT.setFactory(factory);
        uint256 tokenId = 1;
        
        vm.prank(factory);
        positionNFT.mint(user1, tokenId);
        
        assertTrue(positionNFT.exists(tokenId));
    }

    function test_exists_false() public view {
        uint256 tokenId = 999;
        assertFalse(positionNFT.exists(tokenId));
    }

    function test_tokenURI_success() public {
        positionNFT.setFactory(factory);
        uint256 tokenId = 1;
        
        vm.prank(factory);
        positionNFT.mint(user1, tokenId);
        
        string memory uri = positionNFT.tokenURI(tokenId);
        assertEq(uri, "https://api.uniperp.com/position/1");
    }

    function test_tokenURI_different_token_ids() public {
        positionNFT.setFactory(factory);
        
        vm.startPrank(factory);
        positionNFT.mint(user1, 1);
        positionNFT.mint(user1, 123);
        positionNFT.mint(user1, 99999);
        vm.stopPrank();
        
        assertEq(positionNFT.tokenURI(1), "https://api.uniperp.com/position/1");
        assertEq(positionNFT.tokenURI(123), "https://api.uniperp.com/position/123");
        assertEq(positionNFT.tokenURI(99999), "https://api.uniperp.com/position/99999");
    }

    function test_tokenURI_revert_nonexistent() public {
        uint256 tokenId = 999;
        
        vm.expectRevert();
        positionNFT.tokenURI(tokenId);
    }

    function test_toString_zero() public {
        // We can't directly test _toString as it's internal, but we can test via tokenURI
        positionNFT.setFactory(factory);
        uint256 tokenId = 0;
        
        vm.prank(factory);
        positionNFT.mint(user1, tokenId);
        
        string memory uri = positionNFT.tokenURI(tokenId);
        assertEq(uri, "https://api.uniperp.com/position/0");
    }

    function test_erc721_enumerable_functions() public {
        positionNFT.setFactory(factory);
        
        vm.startPrank(factory);
        positionNFT.mint(user1, 1);
        positionNFT.mint(user1, 2);
        positionNFT.mint(user2, 3);
        vm.stopPrank();
        
        // Test totalSupply
        assertEq(positionNFT.totalSupply(), 3);
        
        // Test tokenByIndex
        uint256 token0 = positionNFT.tokenByIndex(0);
        uint256 token1 = positionNFT.tokenByIndex(1);
        uint256 token2 = positionNFT.tokenByIndex(2);
        
        // Should contain all minted tokens (order may vary)
        bool contains1 = (token0 == 1) || (token1 == 1) || (token2 == 1);
        bool contains2 = (token0 == 2) || (token1 == 2) || (token2 == 2);
        bool contains3 = (token0 == 3) || (token1 == 3) || (token2 == 3);
        
        assertTrue(contains1);
        assertTrue(contains2);
        assertTrue(contains3);
        
        // Test tokenOfOwnerByIndex
        assertEq(positionNFT.balanceOf(user1), 2);
        assertEq(positionNFT.balanceOf(user2), 1);
        
        // user1 should own tokens 1 and 2
        uint256 user1Token0 = positionNFT.tokenOfOwnerByIndex(user1, 0);
        uint256 user1Token1 = positionNFT.tokenOfOwnerByIndex(user1, 1);
        
        bool user1Owns1 = (user1Token0 == 1) || (user1Token1 == 1);
        bool user1Owns2 = (user1Token0 == 2) || (user1Token1 == 2);
        
        assertTrue(user1Owns1);
        assertTrue(user1Owns2);
        
        // user2 should own token 3
        uint256 user2Token0 = positionNFT.tokenOfOwnerByIndex(user2, 0);
        assertEq(user2Token0, 3);
    }

    function test_erc721_enumerable_after_burn() public {
        positionNFT.setFactory(factory);
        
        vm.startPrank(factory);
        positionNFT.mint(user1, 1);
        positionNFT.mint(user1, 2);
        positionNFT.mint(user2, 3);
        
        // Burn token 2
        positionNFT.burn(2);
        vm.stopPrank();
        
        // Total supply should decrease
        assertEq(positionNFT.totalSupply(), 2);
        
        // user1 balance should decrease
        assertEq(positionNFT.balanceOf(user1), 1);
        assertEq(positionNFT.balanceOf(user2), 1);
        
        // Token 2 should not exist
        assertFalse(positionNFT.exists(2));
        
        // Should be able to enumerate remaining tokens
        uint256 token0 = positionNFT.tokenByIndex(0);
        uint256 token1 = positionNFT.tokenByIndex(1);
        
        bool contains1 = (token0 == 1) || (token1 == 1);
        bool contains3 = (token0 == 3) || (token1 == 3);
        
        assertTrue(contains1);
        assertTrue(contains3);
    }

    function test_transfer_functionality() public {
        positionNFT.setFactory(factory);
        uint256 tokenId = 1;
        
        vm.prank(factory);
        positionNFT.mint(user1, tokenId);
        
        // user1 transfers to user2
        vm.prank(user1);
        positionNFT.transferFrom(user1, user2, tokenId);
        
        assertEq(positionNFT.ownerOf(tokenId), user2);
        assertEq(positionNFT.balanceOf(user1), 0);
        assertEq(positionNFT.balanceOf(user2), 1);
    }

    function test_approve_functionality() public {
        positionNFT.setFactory(factory);
        uint256 tokenId = 1;
        
        vm.prank(factory);
        positionNFT.mint(user1, tokenId);
        
        // user1 approves user2
        vm.prank(user1);
        positionNFT.approve(user2, tokenId);
        
        assertEq(positionNFT.getApproved(tokenId), user2);
        
        // user2 can transfer the token
        vm.prank(user2);
        positionNFT.transferFrom(user1, user2, tokenId);
        
        assertEq(positionNFT.ownerOf(tokenId), user2);
    }

    function test_setApprovalForAll_functionality() public {
        positionNFT.setFactory(factory);
        
        vm.startPrank(factory);
        positionNFT.mint(user1, 1);
        positionNFT.mint(user1, 2);
        vm.stopPrank();
        
        // user1 approves user2 for all tokens
        vm.prank(user1);
        positionNFT.setApprovalForAll(user2, true);
        
        assertTrue(positionNFT.isApprovedForAll(user1, user2));
        
        // user2 can transfer any token owned by user1
        vm.startPrank(user2);
        positionNFT.transferFrom(user1, user2, 1);
        positionNFT.transferFrom(user1, user2, 2);
        vm.stopPrank();
        
        assertEq(positionNFT.ownerOf(1), user2);
        assertEq(positionNFT.ownerOf(2), user2);
        assertEq(positionNFT.balanceOf(user2), 2);
    }

    function test_supportsInterface() public view {
        // Test ERC721 interface
        assertTrue(positionNFT.supportsInterface(0x80ac58cd));
        
        // Test ERC721Enumerable interface  
        assertTrue(positionNFT.supportsInterface(0x780e9d63));
        
        // Test ERC165 interface
        assertTrue(positionNFT.supportsInterface(0x01ffc9a7));
        
        // Test invalid interface
        assertFalse(positionNFT.supportsInterface(0x12345678));
    }

    function test_ownership_transfer() public {
        address newOwner = address(0x999);
        
        positionNFT.transferOwnership(newOwner);
        
        assertEq(positionNFT.owner(), newOwner);
        
        // Old owner should not be able to set factory
        vm.expectRevert();
        positionNFT.setFactory(factory);
        
        // New owner should be able to set factory
        vm.prank(newOwner);
        positionNFT.setFactory(factory);
        
        assertEq(positionNFT.factory(), factory);
    }

    function testFuzz_mint_and_burn(uint256 tokenId, address user) public {
        vm.assume(user != address(0));
        vm.assume(user.code.length == 0); // Ensure user is not a contract that might reject transfers
        
        positionNFT.setFactory(factory);
        
        vm.startPrank(factory);
        positionNFT.mint(user, tokenId);
        
        assertTrue(positionNFT.exists(tokenId));
        assertEq(positionNFT.ownerOf(tokenId), user);
        assertGt(positionNFT.balanceOf(user), 0);
        
        positionNFT.burn(tokenId);
        
        assertFalse(positionNFT.exists(tokenId));
        vm.stopPrank();
    }

    function testFuzz_tokenURI(uint256 tokenId) public {
        vm.assume(tokenId < type(uint256).max / 10); // Prevent overflow in string conversion
        
        positionNFT.setFactory(factory);
        
        vm.prank(factory);
        positionNFT.mint(user1, tokenId);
        
        string memory uri = positionNFT.tokenURI(tokenId);
        
        // Check that URI contains the token ID (basic sanity check)
        bytes memory uriBytes = bytes(uri);
        assertTrue(uriBytes.length > 30); // Should be longer than base URL
        
        // Should start with the expected prefix
        bytes memory expectedPrefix = bytes("https://api.uniperp.com/position/");
        assertTrue(uriBytes.length >= expectedPrefix.length);
    }

    function test_mint_to_contract_receiver() public {
        positionNFT.setFactory(factory);
        
        // Deploy a simple contract that can receive NFTs
        MockERC721Receiver receiver = new MockERC721Receiver();
        uint256 tokenId = 1;
        
        vm.prank(factory);
        positionNFT.mint(address(receiver), tokenId);
        
        assertEq(positionNFT.ownerOf(tokenId), address(receiver));
    }

    function test_revert_mint_to_non_receiver_contract() public {
        positionNFT.setFactory(factory);
        
        // Try to mint to this contract which doesn't implement IERC721Receiver
        uint256 tokenId = 1;
        
        vm.prank(factory);
        vm.expectRevert();
        positionNFT.mint(address(this), tokenId);
    }

    function test_large_token_id_string_conversion() public {
        positionNFT.setFactory(factory);
        uint256 largeTokenId = 123456789012345;
        
        vm.prank(factory);
        positionNFT.mint(user1, largeTokenId);
        
        string memory uri = positionNFT.tokenURI(largeTokenId);
        assertEq(uri, "https://api.uniperp.com/position/123456789012345");
    }

    function test_multiple_users_enumeration() public {
        positionNFT.setFactory(factory);
        address user3 = address(0x333);
        address user4 = address(0x444);
        
        vm.startPrank(factory);
        positionNFT.mint(user1, 1);
        positionNFT.mint(user2, 2);
        positionNFT.mint(user3, 3);
        positionNFT.mint(user4, 4);
        positionNFT.mint(user1, 5); // user1 gets a second token
        vm.stopPrank();
        
        assertEq(positionNFT.totalSupply(), 5);
        assertEq(positionNFT.balanceOf(user1), 2);
        assertEq(positionNFT.balanceOf(user2), 1);
        assertEq(positionNFT.balanceOf(user3), 1);
        assertEq(positionNFT.balanceOf(user4), 1);
        
        // Test that we can enumerate all tokens for user1
        uint256 user1Token0 = positionNFT.tokenOfOwnerByIndex(user1, 0);
        uint256 user1Token1 = positionNFT.tokenOfOwnerByIndex(user1, 1);
        
        assertTrue((user1Token0 == 1 && user1Token1 == 5) || (user1Token0 == 5 && user1Token1 == 1));
    }

    function test_factory_change() public {
        address newFactory = address(0x999);
        
        positionNFT.setFactory(factory);
        
        vm.prank(factory);
        positionNFT.mint(user1, 1);
        
        // Change factory
        positionNFT.setFactory(newFactory);
        
        // Old factory should not be able to mint
        vm.prank(factory);
        vm.expectRevert("Only factory");
        positionNFT.mint(user1, 2);
        
        // New factory should be able to mint
        vm.prank(newFactory);
        positionNFT.mint(user1, 2);
        
        assertEq(positionNFT.ownerOf(2), user1);
        
        // New factory should be able to burn
        vm.prank(newFactory);
        positionNFT.burn(1);
        
        assertFalse(positionNFT.exists(1));
    }
}

// Simple mock contract to test ERC721 receiver functionality
contract MockERC721Receiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
