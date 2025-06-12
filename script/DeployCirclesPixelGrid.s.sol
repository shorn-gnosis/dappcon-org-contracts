// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/CirclesPixelGrid.sol";

contract DeployCirclesPixelGrid is Script {
    // Gnosis Chain (xDai) Hub Address (User confirmed this is the correct one)
    address constant GNOSIS_HUB_ADDRESS = 0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8;
    // Chiado Testnet Hub Address (Same as Gnosis?)
    // address constant CHIADO_HUB_ADDRESS = 0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8;

    function run() external returns (CirclesPixelGrid) {
        // Get deployer private key from environment or use default Foundry sender
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS"); // Optional: use if no private key

        // Select Hub Address based on network (or use env var)
        // Using Gnosis Chain Hub Address
        address hub = GNOSIS_HUB_ADDRESS;
        string memory orgName = vm.envOr("ORG_NAME", string("Circles Pixel Grid Org")); // Default org name

        console.log("Deploying CirclesPixelGrid to Gnosis Chain...");
        console.log("  Org Name:", orgName);
        console.log("  Hub Address:", hub);
        console.log(
            "  Deployer:",
            deployerPrivateKey != 0
                ? vm.addr(deployerPrivateKey)
                : (deployerAddress != address(0) ? deployerAddress : msg.sender)
        );

        vm.startBroadcast(deployerPrivateKey); // Use private key if provided

        CirclesPixelGrid pixelGrid = new CirclesPixelGrid(orgName, hub);

        vm.stopBroadcast();

        console.log("CirclesPixelGrid deployed at:", address(pixelGrid));
        console.log("Owner:", pixelGrid.owner());
        console.log("Registered:", pixelGrid.isRegistered());

        return pixelGrid;
    }
}
