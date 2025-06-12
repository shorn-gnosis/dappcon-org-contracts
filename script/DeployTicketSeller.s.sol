// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/CRCNFTTicketSeller.sol";

contract DeployTicketSeller is Script {
    function run() external {
        // Start broadcasting transactions
        vm.startBroadcast();
        // @todo
        // Deploy with organization name and registration flag
        //CRCNFTTicketSeller ticketSeller = new CRCNFTTicketSeller("NFT Ticket Seller", true);

        // Log the deployed contract address
        //console.log("CRCNFTTicketSeller deployed at:", address(ticketSeller));

        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}
