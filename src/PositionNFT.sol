// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title PositionNFT - Minimal ERC721 for perpetual positions
/// @notice Only handles NFT minting/burning, delegates business logic to factory
contract PositionNFT is ERC721, ERC721Enumerable, Ownable {
    address public factory;
    
    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory");
        _;
    }

    constructor() ERC721("Perpetual Position NFT", "PERPNFT") Ownable(msg.sender) {}

    function setFactory(address _factory) external onlyOwner {
        factory = _factory;
    }

    function mint(address to, uint256 tokenId) external onlyFactory {
        _safeMint(to, tokenId);
    }

    function burn(uint256 tokenId) external onlyFactory {
        _burn(tokenId);
    }

    function exists(uint256 tokenId) external view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    // Required overrides for ERC721Enumerable
    function _increaseBalance(address account, uint128 amount) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, amount);
    }

    function _update(address to, uint256 tokenId, address auth) internal override(ERC721, ERC721Enumerable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // Minimal tokenURI for positions
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return string(abi.encodePacked("https://api.uniperp.com/position/", _toString(tokenId)));
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
