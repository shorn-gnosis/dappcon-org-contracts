// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/NFTSellerNoArgs.sol";

contract UpdateNFTContract is Script {
    function run() external {
        // Get private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Get seller contract address from environment
        address sellerContract = vm.envAddress("SELLER_ADDRESS");

        // Get correct NFT contract address from environment
        address correctNFTContract = vm.envAddress("CORRECT_NFT_CONTRACT");

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Update the NFT contract address
        NFTSellerNoArgs(sellerContract).configureNFTContract(correctNFTContract);

        // Stop broadcasting
        vm.stopBroadcast();

        console.log("Updated NFT contract address to: %s", correctNFTContract);
    }
}
