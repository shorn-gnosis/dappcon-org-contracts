// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/NFTSellerFactory.sol";

contract DeployNFTSellerFactory is Script {
    function run() external {
        // Start broadcasting transactions
        vm.startBroadcast();
        
        // Deploy the factory contract
        NFTSellerFactory factory = new NFTSellerFactory();
        
        // Log the deployed contract address
        console.log("NFTSellerFactory deployed at:", address(factory));
        
        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}
