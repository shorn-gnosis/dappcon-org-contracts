// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/NFTSellerNoArgs.sol";

contract AddNFTTokenIds is Script {
    function run() external {
        // Get the NFT seller address from environment variable
        string memory sellerAddressStr = vm.envString("SELLER_ADDRESS");
        address sellerAddress = vm.parseAddress(sellerAddressStr);
        
        // Get token IDs from environment variable
        // Format: comma-separated list of token IDs, e.g., "1,2,3,4,5"
        string memory tokenIdsStr = vm.envString("TOKEN_IDS");
        
        // Parse token IDs
        uint256[] memory tokenIds = parseTokenIds(tokenIdsStr);
        
        // Start broadcasting transactions
        vm.startBroadcast();
        
        // Add token IDs to the NFT seller
        NFTSellerNoArgs seller = NFTSellerNoArgs(sellerAddress);
        seller.addAvailableTokenIds(tokenIds);
        
        // Log the number of token IDs added
        console.log("Added", tokenIds.length, "token IDs to NFT seller at:", sellerAddress);
        
        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
    
    // Helper function to parse comma-separated token IDs
    function parseTokenIds(string memory tokenIdsStr) internal pure returns (uint256[] memory) {
        // Count commas to determine array size
        uint256 count = 1; // At least one token ID
        bytes memory tokenIdsBytes = bytes(tokenIdsStr);
        for (uint256 i = 0; i < tokenIdsBytes.length; i++) {
            if (tokenIdsBytes[i] == ',') {
                count++;
            }
        }
        
        // Create array of token IDs
        uint256[] memory tokenIds = new uint256[](count);
        
        // Parse token IDs
        uint256 tokenIdIndex = 0;
        uint256 currentTokenId = 0;
        for (uint256 i = 0; i < tokenIdsBytes.length; i++) {
            if (tokenIdsBytes[i] >= '0' && tokenIdsBytes[i] <= '9') {
                currentTokenId = currentTokenId * 10 + uint256(uint8(tokenIdsBytes[i]) - 48); // Convert ASCII to number
            } else if (tokenIdsBytes[i] == ',') {
                tokenIds[tokenIdIndex] = currentTokenId;
                tokenIdIndex++;
                currentTokenId = 0;
            }
        }
        
        // Add the last token ID
        tokenIds[tokenIdIndex] = currentTokenId;
        
        return tokenIds;
    }
}
