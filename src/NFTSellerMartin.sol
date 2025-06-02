// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC1155Receiver {
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external returns (bytes4);

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external returns (bytes4);
}

interface IERC1155 {
    function balanceOf(address account, uint256 id) external view returns (uint256);
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) external;
}

interface IERC721 {
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface IHub {
    function registerOrganization(string calldata _name, bytes32 _metadataDigest) external;
    function trust(address _trustReceiver, uint96 _expiry) external;
}

contract OrgAccount is IERC1155Receiver {
    address public constant TRUSTED_ADDRESS = 0x42cEDde51198D1773590311E2A340DC06B24cB37;
    IHub public hub = IHub(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8);
        // NFT details
    address public nftContract;
    uint256 public nftTokenId;
    bool public nftLoaded;
    address public owner = msg.sender;

    constructor() {
        hub.registerOrganization("NFT vending machine", 0);
        hub.trust(TRUSTED_ADDRESS, uint96(block.timestamp + (100 * 365 days)));
    }

    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external override returns (bytes4) {
        if (!nftLoaded || value < 10**19) {
        // Return the tokens if conditions aren't met
        IERC1155(address(hub)).safeTransferFrom(address(this), from, id, value, "");
        } else {
            // Mark NFT as claimed and transfer it
            nftLoaded = false;
            try IERC721(nftContract).safeTransferFrom(address(this), from, nftTokenId) {
                // success
            } catch {
                // NFT transfer failed, refund CRC
                nftLoaded = true;
                IERC1155(address(hub)).safeTransferFrom(address(this), from, id, value, "");
            }
        }
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external override returns (bytes4) {
        for (uint256 i = 0; i < ids.length; i++) {
            if (nftLoaded && values[i] >= 10**19) {
                nftLoaded = false;
                try IERC721(nftContract).safeTransferFrom(address(this), from, nftTokenId) {
                    // success
                } catch {
                    // NFT transfer failed, refund CRC
                    IERC1155(address(hub)).safeTransferFrom(address(this), from, ids[i], values[i], "");
                }
                break;
            } else {
                IERC1155(address(hub)).safeTransferFrom(address(this), from, ids[i], values[i], "");
            }
        }
        return this.onERC1155BatchReceived.selector;
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4) {
        require(!nftLoaded, "NFT already loaded");
        nftContract = msg.sender;
        nftTokenId = tokenId;
        nftLoaded = true;
        return this.onERC721Received.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || interfaceId == 0x01ffc9a7;
    }
}