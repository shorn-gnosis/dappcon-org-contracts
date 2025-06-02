// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {BackerNFTSellerFactory} from "../src/BackerNFTSellerFactory.sol";

/**
 * @title DeployBackerNFTSellerFactory
 * @notice Script to deploy the BackerNFTSellerFactory contract
 */
contract DeployBackerNFTSellerFactory is Script {
    function run() external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        BackerNFTSellerFactory factory = new BackerNFTSellerFactory();
        console.log("BackerNFTSellerFactory deployed at:", address(factory));

        vm.stopBroadcast();
        return address(factory);
    }
}
