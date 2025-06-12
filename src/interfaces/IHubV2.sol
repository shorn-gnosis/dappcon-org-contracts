// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

interface IHubV2 {
    function registerOrganization(string calldata _name, bytes32 _metadataDigest) external;
    function trust(address _trustReceiver, uint96 _expiry) external;
    function isTrusted(address _truster, address _trustee) external view returns (bool);
    function isHuman(address avatar) external view returns (bool);
    function day(uint256 _timestamp) external view returns (uint64);
}
