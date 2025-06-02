// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {BackerNFTSellerFactory, BackerNFTSellerParams} from "../src/BackerNFTSellerFactory.sol";
import {BackerNFTSeller} from "../src/BackerNFTSeller.sol";

/**
 * @title CreateBackerNFTSeller
 * @notice Script to create a BackerNFTSeller instance using the factory
 */
contract CreateBackerNFTSeller is Script {
    function run() external returns (address) {
        // --- Configuration ---
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address factoryAddress = vm.envAddress("FACTORY_ADDRESS"); // Address of the deployed BackerNFTSellerFactory

        // Seller parameters from environment variables
        string memory orgName = vm.envString("ORG_NAME");
        address trustedAddr = vm.envAddress("TRUSTED_ADDRESS");
        address nftContract = vm.envAddress("NFT_CONTRACT");
        uint256 offerPrice = vm.envUint("OFFER_PRICE"); // Price in CRC (e.g., 5e18 for 5 CRC)

        // Optional parameters (provide defaults if not set)
        uint256 offerStart = vm.envOr("OFFER_START", uint256(0)); // Defaults to 0 (factory sets to block.timestamp)
        uint256 offerEnd = vm.envOr("OFFER_END", uint256(0)); // Defaults to 0 (factory sets to 100 years)
        address requireTrustedBy = vm.envOr("REQUIRE_TRUSTED_BY", address(0)); // Defaults to address(0)
        bool oncePerUser = vm.envOr("ONCE_PER_USER", bool(false)); // Defaults to false
        bool oncePerDay = vm.envOr("ONCE_PER_DAY", bool(false)); // Defaults to false
        address backerGroupAddress = vm.envOr("BACKER_GROUP_ADDRESS", address(0)); // Defaults to address(0) (no backer check)

        // --- Validation ---
        require(factoryAddress != address(0), "FACTORY_ADDRESS not set");
        require(bytes(orgName).length > 0, "ORG_NAME not set");
        require(trustedAddr != address(0), "TRUSTED_ADDRESS not set");
        require(nftContract != address(0), "NFT_CONTRACT not set");
        require(offerPrice > 0, "OFFER_PRICE must be greater than 0");

        // --- Execution ---
        vm.startBroadcast(deployerPrivateKey);

        BackerNFTSellerFactory factory = BackerNFTSellerFactory(factoryAddress);

        BackerNFTSellerParams memory params = BackerNFTSellerParams({
            orgName: orgName,
            trustedAddr: trustedAddr,
            offerStart: offerStart,
            offerEnd: offerEnd,
            offerPrice: offerPrice,
            requireTrustedBy: requireTrustedBy,
            oncePerUser: oncePerUser,
            oncePerDay: oncePerDay,
            nftContract: nftContract,
            backerGroupAddress: backerGroupAddress // Include new param
        });

        address sellerAddress = factory.createBackerNFTSeller(params);

        console.log("BackerNFTSeller created at:", sellerAddress);
        console.log("  Owner:", BackerNFTSeller(sellerAddress).owner()); // Should be msg.sender of the script tx
        console.log("  Org Name:", params.orgName);
        console.log("  Trusted Address:", params.trustedAddr);
        console.log("  NFT Contract:", params.nftContract);
        console.log("  Offer Price (CRC):", params.offerPrice);
        console.log("  Offer Start:", params.offerStart == 0 ? "Now" : vm.toString(params.offerStart));
        console.log("  Offer End:", params.offerEnd == 0 ? "100 Years" : vm.toString(params.offerEnd));
        console.log("  Require Trusted By:", params.requireTrustedBy);
        console.log("  Once Per User:", params.oncePerUser);
        console.log("  Once Per Day:", params.oncePerDay);
        console.log("  Backer Group Address:", params.backerGroupAddress);

        vm.stopBroadcast();
        return sellerAddress;
    }
}
