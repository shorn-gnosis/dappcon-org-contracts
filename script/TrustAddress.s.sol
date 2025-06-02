// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/CRCNFTTicketSeller.sol";

contract TrustAddress is Script {
    function run() external {
        // Get the address to trust from command line arguments
        string memory addressToTrustStr = vm.envString("ADDRESS_TO_TRUST");
        address addressToTrust = vm.parseAddress(addressToTrustStr);
        
        // Get the contract address from environment variable
        string memory contractAddressStr = vm.envString("CONTRACT_ADDRESS");
        address contractAddress = vm.parseAddress(contractAddressStr);
        
        // Start broadcasting transactions
        vm.startBroadcast();
        
        // Get your contract instance
        CRCNFTTicketSeller ticketSeller = CRCNFTTicketSeller(contractAddress);
        
        // Trust the address with a 100-year expiry
        uint96 expiry = uint96(block.timestamp + (100 * 365 days));
        ticketSeller.setTrustedAddress(addressToTrust, expiry);
        
        // Log the trusted address
        console.log("Trusted address:", addressToTrust);
        console.log("Expiry timestamp:", expiry);
        
        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}
