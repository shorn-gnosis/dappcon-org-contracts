// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/* ========== INTERFACES ========== */

interface IERC1155Receiver {
    function onERC1155Received(address operator, address from, uint256 id, uint256 value, bytes calldata data)
        external
        returns (bytes4);

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external returns (bytes4);
}

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}

interface IERC1155 {
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external;
}

interface IERC721 {
    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    function ownerOf(uint256 tokenId) external view returns (address);
}

interface IHub {
    function registerOrganization(string calldata _name, bytes32 _metadataDigest) external;
    function trust(address _trustReceiver, uint96 _expiry) external;
    function isTrusted(address _truster, address _trustee) external view returns (bool);
}

/* ========== MAIN CONTRACT ========== */

/**
 * @title BackerNFTSeller
 * @notice A contract that:
 *  - Registers as an org via a Hub
 *  - Accepts any CRC tokens from the hub
 *  - Transfers an NFT as a reward, subject to time/usage/trust/backer constraints, then forwards the CRC tokens to the owner
 *  - For batch transfers, sums up all token values
 *  - Allows the owner to add and withdraw NFTs
 *  - Includes an optional check to ensure the user is trusted by a specific 'backer group' via the Hub.
 */
contract BackerNFTSeller is IERC1155Receiver, IERC721Receiver {
    // ---------- State Variables ----------

    address public owner;

    // Hub / trust
    address public hubAddress;
    bool public isRegistered;
    address public trustedAddress;

    // The derived ERC1155 token ID
    uint256 public acceptedId;

    // Offer constraints
    string public orgName;
    uint256 public offerStart;
    uint256 public offerEnd;
    uint256 public offerPrice;
    bool public oncePerUser;
    bool public oncePerDay;
    address public requireTrustedBy;
    address public backerGroupAddress; // NEW: Address of the group to check for backer status

    // NFT reward
    address public nftContract;
    uint256[] public availableTokenIds;

    // Usage tracking
    mapping(address => bool) public usedOnce;
    mapping(address => uint256) public lastUsage;

    // ---------- Events ----------

    event CRCRefunded(address indexed user, uint256 id, uint256 value, string reason);
    event NFTRewarded(address indexed user, uint256 tokenId);
    event OfferClaimed(address indexed user, uint256 id, uint256 value);
    event NFTDeposited(address indexed depositor, uint256 tokenId);
    event NFTWithdrawn(address indexed withdrawer, uint256 tokenId);
    event BackerGroupConfigured(address indexed backerGroup); // NEW Event

    // ---------- Constructor ----------

    constructor() {
        owner = msg.sender;
    }

    // ---------- Modifiers ----------

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // ---------- Admin Setup ----------

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
        trustedAddress = _trustedAddress;
        acceptedId = uint256(uint160(_trustedAddress));
    }

    function configureNFTContract(address _nftContract) external onlyOwner {
        nftContract = _nftContract;
    }

    function addAvailableTokenIds(uint256[] calldata tokenIds) external onlyOwner {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            availableTokenIds.push(tokenIds[i]);
        }
    }

    function configureOffer(
        uint256 _offerStart,
        uint256 _offerEnd,
        uint256 _offerPrice,
        address _requireTrustedBy,
        bool _oncePerUser,
        bool _oncePerDay
    ) external onlyOwner {
        offerStart = _offerStart;
        offerEnd = _offerEnd;
        offerPrice = _offerPrice;
        requireTrustedBy = _requireTrustedBy;
        oncePerUser = _oncePerUser;
        oncePerDay = _oncePerDay;
    }

    // NEW: Configure the backer group address
    function configureBackerGroup(address _backerGroupAddress) external onlyOwner {
        backerGroupAddress = _backerGroupAddress;
        emit BackerGroupConfigured(_backerGroupAddress);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        owner = newOwner;
    }

    function withdrawNFTs(uint256[] calldata tokenIds) external onlyOwner {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            IERC721(nftContract).safeTransferFrom(address(this), owner, tokenIds[i]);
            emit NFTWithdrawn(msg.sender, tokenIds[i]);
        }
    }

    // ---------- ERC1155 Receiving (Single) ----------

    function onERC1155Received(address, /*operator*/ address from, uint256 id, uint256 value, bytes calldata /*data*/ )
        external
        override
        returns (bytes4)
    {
        if (msg.sender != hubAddress) {
            IERC1155(msg.sender).safeTransferFrom(address(this), from, id, value, "");
            emit CRCRefunded(from, id, value, "Not from Hub");
            return this.onERC1155Received.selector;
        }

        (bool ok, string memory reason) = _checkClaim(from, value);
        if (!ok) {
            IERC1155(msg.sender).safeTransferFrom(address(this), from, id, value, "");
            emit CRCRefunded(from, id, value, reason);
        } else {
            _executeClaim(from, msg.sender, id, value);
        }
        return this.onERC1155Received.selector;
    }

    // ---------- ERC1155 Receiving (Batch) ----------

    function onERC1155BatchReceived(
        address, /*operator*/
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata /*data*/
    ) external override returns (bytes4) {
        if (msg.sender != hubAddress) {
            for (uint256 i = 0; i < ids.length; i++) {
                IERC1155(msg.sender).safeTransferFrom(address(this), from, ids[i], values[i], "");
                emit CRCRefunded(from, ids[i], values[i], "Not from Hub");
            }
            return this.onERC1155BatchReceived.selector;
        }

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < ids.length; i++) {
            totalAmount += values[i];
        }

        (bool ok, string memory reason) = _checkClaim(from, totalAmount);
        if (!ok || totalAmount < offerPrice) {
            for (uint256 i = 0; i < ids.length; i++) {
                IERC1155(msg.sender).safeTransferFrom(address(this), from, ids[i], values[i], "");
                emit CRCRefunded(from, ids[i], values[i], (!ok) ? reason : "Insufficient total CRC");
            }
            return this.onERC1155BatchReceived.selector;
        }

        if (availableTokenIds.length == 0) {
            for (uint256 i = 0; i < ids.length; i++) {
                IERC1155(msg.sender).safeTransferFrom(address(this), from, ids[i], values[i], "");
                emit CRCRefunded(from, ids[i], values[i], "No NFTs available");
            }
            return this.onERC1155BatchReceived.selector;
        }

        if (oncePerUser) usedOnce[from] = true;
        if (oncePerDay) lastUsage[from] = block.timestamp;

        uint256 nftTokenId = availableTokenIds[availableTokenIds.length - 1];

        try IERC721(nftContract).safeTransferFrom(address(this), from, nftTokenId) {
            availableTokenIds.pop();
            for (uint256 i = 0; i < ids.length; i++) {
                IERC1155(msg.sender).safeTransferFrom(address(this), owner, ids[i], values[i], "");
            }
            emit NFTRewarded(from, nftTokenId);
            emit OfferClaimed(from, acceptedId, totalAmount);
        } catch {
            if (oncePerUser) usedOnce[from] = false;
            if (oncePerDay) lastUsage[from] = 0;
            for (uint256 i = 0; i < ids.length; i++) {
                IERC1155(msg.sender).safeTransferFrom(address(this), from, ids[i], values[i], "");
                emit CRCRefunded(from, ids[i], values[i], "NFT transfer failed");
            }
        }

        return this.onERC1155BatchReceived.selector;
    }

    // ---------- ERC721 Receiving ----------

    function onERC721Received(address, /*operator*/ address from, uint256 tokenId, bytes calldata /*data*/ )
        external
        override
        returns (bytes4)
    {
        require(from == owner || msg.sender == nftContract, "Only owner or NFT contract can deposit NFTs");
        availableTokenIds.push(tokenId);
        emit NFTDeposited(from, tokenId);
        return this.onERC721Received.selector;
    }

    // ---------- Internal Claim Checking ----------

    function _checkClaim(address user, uint256 totalAmount) internal view returns (bool, string memory) {
        if (!isRegistered) return (false, "Not registered");
        if (block.timestamp < offerStart) return (false, "Offer not started");
        if (block.timestamp > offerEnd) return (false, "Offer ended");
        if (oncePerUser && usedOnce[user]) return (false, "Already used");
        if (oncePerDay && (lastUsage[user] + 1 days > block.timestamp)) return (false, "Used today");
        if (totalAmount < offerPrice) return (false, "Not enough CRC");
        if (availableTokenIds.length == 0) return (false, "No NFTs available");

        // Check if requireTrustedBy trusts 'user'
        if (requireTrustedBy != address(0)) {
            bool isOk = IHub(hubAddress).isTrusted(requireTrustedBy, user);
            if (!isOk) return (false, "User not trusted by requireTrustedBy");
        }

        // NEW: Check if user is trusted by the backer group
        if (backerGroupAddress != address(0)) {
            bool isBacker = IHub(hubAddress).isTrusted(backerGroupAddress, user);
            if (!isBacker) return (false, "User is not a backer");
        }

        return (true, "");
    }

    function _executeClaim(
        address from,
        address hubSender,
        uint256 tokenId, // Note: This is the CRC token ID, not NFT
        uint256 value
    ) internal {
        if (availableTokenIds.length == 0) {
            IERC1155(hubSender).safeTransferFrom(address(this), from, tokenId, value, "");
            emit CRCRefunded(from, tokenId, value, "No NFTs available");
            return;
        }

        if (oncePerUser) usedOnce[from] = true;
        if (oncePerDay) lastUsage[from] = block.timestamp;

        uint256 nftTokenId = availableTokenIds[availableTokenIds.length - 1];

        try IERC721(nftContract).safeTransferFrom(address(this), from, nftTokenId) {
            availableTokenIds.pop();
            IERC1155(hubSender).safeTransferFrom(address(this), owner, tokenId, value, "");
            emit NFTRewarded(from, nftTokenId);
            emit OfferClaimed(from, tokenId, value);
        } catch {
            if (oncePerUser) usedOnce[from] = false;
            if (oncePerDay) lastUsage[from] = 0;
            IERC1155(hubSender).safeTransferFrom(address(this), from, tokenId, value, "");
            emit CRCRefunded(from, tokenId, value, "NFT transfer failed");
        }
    }

    // ---------- ERC165 ----------
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || interfaceId == type(IERC721Receiver).interfaceId
            || interfaceId == 0x01ffc9a7; // ERC165 Interface ID
    }
}
