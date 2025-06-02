// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC721 {
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
}

interface IHub {
    function registerOrganization(string calldata _name, bytes32 _metadataDigest) external;
    function trust(address _trustReceiver, uint96 _expiry) external;
}

contract CRCNFTTicketSeller {
    address public owner;
    IERC721 public nft;
    uint256 public ticketPriceCRC;
    uint256 public maxTickets;
    uint256 public ticketsSold;

    address public hubAddress;
    uint256[] public availableTokenIds;
    
    // Organization status
    bool public isRegistered;
    string public orgName;

    event TicketSold(address indexed buyer, uint256 tokenId);
    event CRCRefunded(address indexed buyer, uint256 amount, string reason);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(string memory _orgName, bool _registerAsOrg) {
        owner = msg.sender;

        nft = IERC721(0xa53A5773b9d4cE2cf5b42A7711239833b31ffc38);
        ticketPriceCRC = 5e18; // price in CRC
        maxTickets = 100; // max tickets available
        hubAddress = 0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8;
        
        // Register as organization if requested
        if (_registerAsOrg) {
            IHub(hubAddress).registerOrganization(_orgName, 0);
            isRegistered = true;
            orgName = _orgName;
            
            // Trust addresses with a long expiry
            uint96 expiry = uint96(block.timestamp + (100 * 365 days));
            
            // Trust these addresses for testing
            IHub(hubAddress).trust(0xc175a0c71f1eDA836ebbF3Ab0e32Fc8865FdEe91, expiry);
            IHub(hubAddress).trust(0x42cEDde51198D1773590311E2A340DC06B24cB37, expiry);
            
        }
    }

    function addAvailableTokenIds(uint256[] calldata tokenIds) external onlyOwner {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            availableTokenIds.push(tokenIds[i]);
        }
    }

    // Organization registration functions
    function setHub(address _hubAddress) external onlyOwner {
        require(hubAddress == address(0), "Hub already set");
        hubAddress = _hubAddress;
    }

    function registerOrg(string calldata _orgName) external onlyOwner {
        require(!isRegistered, "Already registered");
        require(hubAddress != address(0), "Hub not set");
        IHub(hubAddress).registerOrganization(_orgName, 0);
        isRegistered = true;
        orgName = _orgName;
    }

    function setTrustedAddress(address _trustedAddress, uint96 _expiry) external onlyOwner {
        require(isRegistered, "Not registered");
        IHub(hubAddress).trust(_trustedAddress, _expiry);
    }

    function onERC1155Received(
        address,
        address from,
        uint256, // id (unused)
        uint256 value,
        bytes calldata
    ) external returns (bytes4) {
        // Check if registered as an organization
        if (!isRegistered) {
            emit CRCRefunded(from, value, "Not registered as organization");
            return this.onERC1155Received.selector;
        }
        
        if (msg.sender != hubAddress) {
            emit CRCRefunded(from, value, "Invalid source");
            return this.onERC1155Received.selector;
        }

        if (ticketsSold >= maxTickets || availableTokenIds.length == 0) {
            emit CRCRefunded(from, value, "Sold out");
            return this.onERC1155Received.selector;
        }

        if (value < ticketPriceCRC) {
            emit CRCRefunded(from, value, "Insufficient CRC");
            return this.onERC1155Received.selector;
        }

        uint256 tokenId = availableTokenIds[availableTokenIds.length - 1];
        availableTokenIds.pop();
        ticketsSold++;

        nft.safeTransferFrom(address(this), from, tokenId);
        emit TicketSold(from, tokenId);

        // Send CRC to owner (your org keeps it)
        // In a real scenario, CRC is a token you'd transfer here

        return this.onERC1155Received.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x4e2312e0;
    }

    function withdrawNFTs(uint256[] calldata tokenIds) external onlyOwner {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            nft.safeTransferFrom(address(this), owner, tokenIds[i]);
        }
    }
}
