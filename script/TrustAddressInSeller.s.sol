// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/NFTSellerNoArgs.sol";

contract TrustAddressInSeller is Script {
    function run() external {
        // Get the NFT seller address from environment variable
        string memory sellerAddressStr = vm.envString("SELLER_ADDRESS");
        address sellerAddress = vm.parseAddress(sellerAddressStr);
        
        // Get the address to trust from environment variable
        string memory trustedAddressStr = vm.envString("TRUSTED_ADDRESS");
        address trustedAddress = vm.parseAddress(trustedAddressStr);
        
        // Get the expiry from environment variable (optional)
        uint96 expiry = uint96(block.timestamp + (100 * 365 days)); // Default: 100 years
        try vm.envString("EXPIRY") returns (string memory val) {
            expiry = uint96(vm.parseUint(val));
        } catch {}
        
        // Start broadcasting transactions
        vm.startBroadcast();
        
        // Trust the address in the NFT seller
        NFTSellerNoArgs seller = NFTSellerNoArgs(sellerAddress);
        seller.setTrustedAddress(trustedAddress, expiry);
        
        // Log the trusted address
        console.log("Trusted address:", trustedAddress);
        console.log("Expiry timestamp:", expiry);
        
        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}
