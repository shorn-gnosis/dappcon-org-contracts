// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.24;

interface INameRegistry {
    function updateMetadataDigest(bytes32 _metadataDigest) external;
    function getMetadataDigest(address _avatar) external view returns (bytes32);
}
