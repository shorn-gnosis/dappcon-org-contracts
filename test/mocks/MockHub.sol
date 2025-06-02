// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC1155Receiver} from "../../src/CirclesPixelGrid.sol"; // Use interface from PixelGrid
import {IERC1155} from "../../src/CirclesPixelGrid.sol";

contract MockHub is IERC1155 {
    mapping(address => mapping(uint256 => uint256)) public balances;
    mapping(address => bool) public isOrgRegistered;

    // Simulate safeTransferFrom being called *by* a user *to* the Hub,
    // which then calls the target receiver.
    // For testing, we'll call this directly from the test contract,
    // simulating the user -> hub -> receiver flow.
    function simulateTransferToReceiver(
        address _from, // The original user sending CRC
        address _to,   // The target contract (e.g., PixelGrid)
        uint256 _id,   // CRC Token ID
        uint256 _value,
        bytes calldata _data
    ) external {
        // In a real Hub, it would check balances[_from] >= _value
        // For mock, assume transfer is valid if called.

        // Decrease sender's balance (optional for mock)
        // balances[_from][_id] -= _value;

        // Increase receiver's balance (simulate holding before forwarding)
        balances[_to][_id] += _value;

        // Call the receiver's hook, setting msg.sender to the Hub's address
        bytes4 result = IERC1155Receiver(_to).onERC1155Received(
            _from, // Operator is the original sender in this context
            _from, // From is the original sender
            _id,
            _value,
            _data
        );
        require(
            result == IERC1155Receiver.onERC1155Received.selector,
            "MockHub: Invalid receiver response"
        );
    }

    // Implement the IERC1155 safeTransferFrom needed by PixelGrid to forward/refund
    // This will be called *by* the PixelGrid contract.
    function safeTransferFrom(
        address _from, // Should be the PixelGrid contract address
        address _to,   // Owner or original buyer (for refunds)
        uint256 _id,
        uint256 _amount,
        bytes calldata /*_data*/
    ) external override {
        require(msg.sender == _from, "MockHub: Transfer not from sender"); // Basic check
        require(balances[_from][_id] >= _amount, "MockHub: Insufficient balance");

        balances[_from][_id] -= _amount;
        balances[_to][_id] += _amount;
        // In a real ERC1155, would also call receiver hooks if _to is a contract
    }

    // Mock registerOrganization
    function registerOrganization(string calldata /*_name*/, bytes32 /*_metadataDigest*/) external {
        isOrgRegistered[msg.sender] = true; // Mark the calling contract as registered
    }

    // --- Unused IERC1155 functions (required by interface) ---
    function safeBatchTransferFrom(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external override {}
    function balanceOf(address, uint256) external view override returns (uint256) { return 0; } // Implement if needed for specific tests
    function balanceOfBatch(address[] calldata, uint256[] calldata) external view override returns (uint256[] memory) {}
    function setApprovalForAll(address, bool) external override {}
    function isApprovedForAll(address, address) external view override returns (bool) { return true; } // Assume approval for simplicity

    // Helper to mint mock tokens for testing
    function mint(address _to, uint256 _id, uint256 _amount) external {
        balances[_to][_id] += _amount;
    }
}
