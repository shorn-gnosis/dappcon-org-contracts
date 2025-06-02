// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/NFTSellerFactory.sol";

contract CreateNFTSeller is Script {
    function run() external {
        // Get the factory address from environment variable
        string memory factoryAddressStr = vm.envString("FACTORY_ADDRESS");
        address factoryAddress = vm.parseAddress(factoryAddressStr);
        
        // Get parameters from environment variables
        string memory orgName = vm.envString("ORG_NAME");
        string memory trustedAddrStr = vm.envString("TRUSTED_ADDRESS");
        address trustedAddr = vm.parseAddress(trustedAddrStr);
        string memory nftContractStr = vm.envString("NFT_CONTRACT");
        address nftContract = vm.parseAddress(nftContractStr);
        string memory offerPriceStr = vm.envString("OFFER_PRICE");
        uint256 offerPrice = vm.parseUint(offerPriceStr);
        
        // Optional parameters with defaults
        uint256 offerStart = block.timestamp;
        uint256 offerEnd = block.timestamp + (100 * 365 days);
        address requireTrustedBy = address(0);
        bool oncePerUser = false;
        bool oncePerDay = false;
        
        // Check for optional environment variables
        try vm.envString("OFFER_START") returns (string memory val) {
            offerStart = vm.parseUint(val);
        } catch {}
        
        try vm.envString("OFFER_END") returns (string memory val) {
            offerEnd = vm.parseUint(val);
        } catch {}
        
        try vm.envString("REQUIRE_TRUSTED_BY") returns (string memory val) {
            requireTrustedBy = vm.parseAddress(val);
        } catch {}
        
        try vm.envString("ONCE_PER_USER") returns (string memory val) {
            oncePerUser = vm.parseUint(val) == 1;
        } catch {}
        
        try vm.envString("ONCE_PER_DAY") returns (string memory val) {
            oncePerDay = vm.parseUint(val) == 1;
        } catch {}
        
        // Create the NFTSellerParams struct
        NFTSellerParams memory params;
        params.orgName = orgName;
        params.trustedAddr = trustedAddr;
        params.offerStart = offerStart;
        params.offerEnd = offerEnd;
        params.offerPrice = offerPrice;
        params.requireTrustedBy = requireTrustedBy;
        params.oncePerUser = oncePerUser;
        params.oncePerDay = oncePerDay;
        params.nftContract = nftContract;
        
        // Start broadcasting transactions
        vm.startBroadcast();
        
        // Create the NFT seller
        NFTSellerFactory factory = NFTSellerFactory(factoryAddress);
        address sellerAddress = factory.createNFTSeller(params);
        
        // Log the deployed contract address
        console.log("NFT Seller deployed at:", sellerAddress);
        
        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}
