// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

contract MockNFT is ERC721 {
    uint256 private _nextTokenId;
    uint256 public constant MAX_SUPPLY = 100;
    
    constructor(
        string memory name,
        string memory symbol
    ) ERC721(name, symbol) {
        
        // Mint 100 tokens to the creator
        for (uint256 i = 0; i < MAX_SUPPLY; i++) {
            uint256 tokenId = _nextTokenId++;
            _safeMint(msg.sender, tokenId);
        }
    }
}