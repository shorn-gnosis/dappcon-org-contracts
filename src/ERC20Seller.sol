// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/* ========== INTERFACES ========== */

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
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) external;
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IHub {
    function registerOrganization(string calldata _name, bytes32 _metadataDigest) external;
    function trust(address _trustReceiver, uint96 _expiry) external;

    // Must exist for the trust check to work:
    function isTrusted(address _truster, address _trustee) external view returns (bool);
}

/* ========== MAIN CONTRACT ========== */

/**
 * @title ERC20SellerNoArgs
 * @notice A no-argument contract that:
 *  - Registers as an org via a Hub
 *  - Accepts exactly one ERC1155 token ID (derived from the trusted address by `uint256(uint160(trustedAddress))`)
 *  - Pays an ERC20 reward, subject to time/usage constraints, then forwards the tokens to the owner
 *  - For batch transfers, requires all token IDs match acceptedId and sums up all values
 *  - Allows leftover reward tokens to be swept out by the owner
 */
contract ERC20SellerNoArgs is IERC1155Receiver {
    // ---------- State Variables ----------

    address public owner;

    // Hub / trust
    address public hubAddress;
    bool    public isRegistered;
    address public trustedAddress;

    // The derived ERC1155 token ID
    uint256 public acceptedId;

    // Offer constraints
    string  public orgName;
    uint256 public offerStart;
    uint256 public offerEnd;
    uint256 public offerPrice;
    bool    public oncePerUser;
    bool    public oncePerDay;
    address public requireTrustedBy; // was 'requiredTruster'

    // Reward
    address public rewardToken;
    uint256 public rewardAmount;

    // Usage tracking
    mapping(address => bool)    public usedOnce;
    mapping(address => uint256) public lastUsage;

    // ---------- Events ----------

    event CRCRefunded(address indexed user, uint256 id, uint256 value, string reason);
    event RewardPaid(address indexed user, uint256 amount);
    event OfferClaimed(address indexed user, uint256 id, uint256 value);
    event SweptTokens(address indexed sweeper, address token, uint256 amount);

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

    /**
     * @notice Sets trustedAddress, calls hub.trust(...),
     *         and auto-derives the 1155 ID by converting address->uint160->uint256.
     *         The expiry is set by the external calls (like factory).
     */
    function setTrustedAddress(address _trustedAddress, uint96 _expiry) external onlyOwner {
        require(isRegistered, "Not registered");
        IHub(hubAddress).trust(_trustedAddress, _expiry);
        trustedAddress = _trustedAddress;

        // Derive the ID from the address
        acceptedId = uint256(uint160(_trustedAddress));
    }

    /**
     * @dev Here we rename 'requiredTruster' → 'requireTrustedBy' in the parameters & storage
     */
    function configureOffer(
        uint256 _offerStart,
        uint256 _offerEnd,
        uint256 _offerPrice,
        address _requireTrustedBy,
        bool _oncePerUser,
        bool _oncePerDay
    ) external onlyOwner {
        offerStart       = _offerStart;
        offerEnd         = _offerEnd;
        offerPrice       = _offerPrice;
        requireTrustedBy = _requireTrustedBy;
        oncePerUser      = _oncePerUser;
        oncePerDay       = _oncePerDay;
    }

    function configureRewardToken(address _rewardToken, uint256 _rewardAmount) external onlyOwner {
        rewardToken  = _rewardToken;
        rewardAmount = _rewardAmount;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        owner = newOwner;
    }

    function sweepTokens(address token) external onlyOwner {
        uint256 bal = IERC20(token).balanceOf(address(this));
        require(bal > 0, "No tokens left");
        IERC20(token).transfer(owner, bal);
        emit SweptTokens(msg.sender, token, bal);
    }

    // ---------- ERC1155 Receiving (Single) ----------

    function onERC1155Received(
        address /*operator*/,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata /*data*/
    ) external override returns (bytes4) {
        // Must come from hub
        if (msg.sender != hubAddress) {
            IERC1155(msg.sender).safeTransferFrom(address(this), from, id, value, "");
            emit CRCRefunded(from, id, value, "Not from Hub");
            return this.onERC1155Received.selector;
        }

        (bool ok, string memory reason) = _checkClaim(from, value);
        if (!ok || id != acceptedId) {
            // Refund
            IERC1155(msg.sender).safeTransferFrom(address(this), from, id, value, "");
            string memory finalReason = (!ok) ? reason : "Not accepted tokenId";
            emit CRCRefunded(from, id, value, finalReason);
        } else {
            _executeClaim(from, msg.sender, id, value);
        }
        return this.onERC1155Received.selector;
    }

    // ---------- ERC1155 Receiving (Batch) ----------

    function onERC1155BatchReceived(
        address /*operator*/,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata /*data*/
    ) external override returns (bytes4) {
        // Must come from hub
        if (msg.sender != hubAddress) {
            // refund everything
            for (uint256 i = 0; i < ids.length; i++) {
                IERC1155(msg.sender).safeTransferFrom(address(this), from, ids[i], values[i], "");
                emit CRCRefunded(from, ids[i], values[i], "Not from Hub");
            }
            return this.onERC1155BatchReceived.selector;
        }

        // 1) Check that all IDs match acceptedId and sum total
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < ids.length; i++) {
            if (ids[i] != acceptedId) {
                // Unaccepted => refund entire batch
                for (uint256 j = 0; j < ids.length; j++) {
                    IERC1155(msg.sender).safeTransferFrom(address(this), from, ids[j], values[j], "");
                    emit CRCRefunded(from, ids[j], values[j], "Not accepted tokenId in batch");
                }
                return this.onERC1155BatchReceived.selector;
            }
            totalAmount += values[i];
        }

        // 2) Check usage/time constraints and if total >= offerPrice
        (bool ok, string memory reason) = _checkClaim(from, totalAmount);
        if (!ok || totalAmount < offerPrice) {
            // refund entire batch
            for (uint256 i = 0; i < ids.length; i++) {
                IERC1155(msg.sender).safeTransferFrom(address(this), from, ids[i], values[i], "");
                emit CRCRefunded(
                    from,
                    ids[i],
                    values[i],
                    (!ok) ? reason : "Insufficient total CRC"
                );
            }
            return this.onERC1155BatchReceived.selector;
        }

        // 3) Attempt reward
        if (oncePerUser) {
            usedOnce[from] = true;
        }
        if (oncePerDay) {
            lastUsage[from] = block.timestamp;
        }

        bool success = IERC20(rewardToken).transfer(from, rewardAmount);
        if (!success) {
            // revert usage
            if (oncePerUser) {
                usedOnce[from] = false;
            }
            if (oncePerDay) {
                lastUsage[from] = 0;
            }
            // refund entire batch
            for (uint256 i = 0; i < ids.length; i++) {
                IERC1155(msg.sender).safeTransferFrom(address(this), from, ids[i], values[i], "");
                emit CRCRefunded(from, ids[i], values[i], "ERC20 transfer failed");
            }
        } else {
            // forward entire batch to owner
            for (uint256 i = 0; i < ids.length; i++) {
                IERC1155(msg.sender).safeTransferFrom(address(this), owner, ids[i], values[i], "");
            }
            emit RewardPaid(from, rewardAmount);
            emit OfferClaimed(from, acceptedId, totalAmount);
        }
        return this.onERC1155BatchReceived.selector;
    }

    // ---------- Internal Claim Checking ----------

    function _checkClaim(address user, uint256 totalAmount)
        internal
        view
        returns (bool, string memory)
    {
        if (!isRegistered) {
            return (false, "Not registered");
        }
        if (block.timestamp < offerStart) {
            return (false, "Offer not started");
        }
        if (block.timestamp > offerEnd) {
            return (false, "Offer ended");
        }
        if (oncePerUser && usedOnce[user]) {
            return (false, "Already used");
        }
        if (oncePerDay && (lastUsage[user] + 1 days > block.timestamp)) {
            return (false, "Used today");
        }
        if (totalAmount < offerPrice) {
            return (false, "Not enough CRC");
        }

        // new logic for requireTrustedBy => user must be trusted by requireTrustedBy
        if (requireTrustedBy != address(0)) {
            // check if requireTrustedBy trusts 'user'
            bool isOk = IHub(hubAddress).isTrusted(requireTrustedBy, user);
            if (!isOk) {
                return (false, "User not trusted by requireTrustedBy");
            }
        }

        uint256 bal = IERC20(rewardToken).balanceOf(address(this));
        if (bal < rewardAmount) {
            return (false, "Not enough reward tokens");
        }
        return (true, "");
    }

    function _executeClaim(
        address from,
        address hubSender,
        uint256 tokenId,
        uint256 value
    ) internal {
        if (oncePerUser) {
            usedOnce[from] = true;
        }
        if (oncePerDay) {
            lastUsage[from] = block.timestamp;
        }

        bool success = IERC20(rewardToken).transfer(from, rewardAmount);
        if (!success) {
            // revert usage
            if (oncePerUser) {
                usedOnce[from] = false;
            }
            if (oncePerDay) {
                lastUsage[from] = 0;
            }
            // Refund
            IERC1155(hubSender).safeTransferFrom(address(this), from, tokenId, value, "");
            emit CRCRefunded(from, tokenId, value, "ERC20 transfer failed");
        } else {
            // forward the CRC deposit
            IERC1155(hubSender).safeTransferFrom(address(this), owner, tokenId, value, "");
            emit RewardPaid(from, rewardAmount);
            emit OfferClaimed(from, tokenId, value);
        }
    }

    // ---------- ERC165 ----------
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == type(IERC1155Receiver).interfaceId ||
            interfaceId == 0x01ffc9a7; 
    }
}

/* ========== FACTORY ========== */

// renamed `requiredTruster` -> `requireTrustedBy` in the struct
struct SellerParams {
    string orgName;
    address trustedAddr;

    uint256 offerStart;
    uint256 offerEnd;
    uint256 offerPrice;
    address requireTrustedBy;
    bool oncePerUser;
    bool oncePerDay;

    address rewardToken;
    uint256 rewardAmount;
}

contract ERC20SellerFactory {
    // Hardcode the hub
    address public constant HARDCODED_HUB = 0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8;

    address[] private _allDeployed;
    address public factoryOwner;

    constructor() {
        factoryOwner = msg.sender;
    }

    modifier onlyFactoryOwner() {
        require(msg.sender == factoryOwner, "Not factory owner");
        _;
    }

    function allDeployments() external view returns (address[] memory) {
        return _allDeployed;
    }

    /**
     * @dev One-click default. 
     */
    function createWithDefaultSeller() external returns (address) {
        // Hard-coded defaults
        SellerParams memory p;
        p.orgName        = "Selling 5 USDC for 100 CRC";
        p.trustedAddr    = 0x42cEDde51198D1773590311E2A340DC06B24cB37;
        p.offerStart     = block.timestamp;
        p.offerEnd       = block.timestamp + (100 * 365 days);
        p.offerPrice     = 100e18;
        p.requireTrustedBy = address(0);
        p.oncePerUser    = false;
        p.oncePerDay     = true;
        p.rewardToken    = 0x2a22f9c3b484c3629090FeED35F17Ff8F88f76F0;
        p.rewardAmount   = 5e6;

        return _deploySeller(p, p.trustedAddr);
    }

    /**
     * @notice createTokenOffer
     */
    function createTokenOffer(SellerParams calldata p) external returns (address) {
        // copy fields
        SellerParams memory mem;
        mem.orgName        = p.orgName;
        mem.trustedAddr    = p.trustedAddr;
        mem.offerStart     = (p.offerStart == 0) ? block.timestamp : p.offerStart;
        mem.offerEnd       = (p.offerEnd == 0)   ? (block.timestamp + (100 * 365 days)) : p.offerEnd;
        mem.offerPrice     = p.offerPrice;
        mem.requireTrustedBy = p.requireTrustedBy;
        mem.oncePerUser    = p.oncePerUser;
        mem.oncePerDay     = p.oncePerDay;
        mem.rewardToken    = p.rewardToken;
        mem.rewardAmount   = p.rewardAmount;

        // finalOwner => msg.sender
        return _deploySeller(mem, msg.sender);
    }

    function _deploySeller(SellerParams memory s, address finalOwner)
        private
        returns (address)
    {
        ERC20SellerNoArgs seller = new ERC20SellerNoArgs();

        // 1) setHub => fixed
        seller.setHub(HARDCODED_HUB);

        // 2) register
        seller.registerOrg(s.orgName);

        // 3) trust => expiry => 100 years from now
        uint96 bigExpiry = uint96(block.timestamp + (100 * 365 days));
        seller.setTrustedAddress(s.trustedAddr, bigExpiry);

        // 4) configureOffer
        seller.configureOffer(
            s.offerStart,
            s.offerEnd,
            s.offerPrice,
            s.requireTrustedBy,
            s.oncePerUser,
            s.oncePerDay
        );

        // 5) reward
        seller.configureRewardToken(s.rewardToken, s.rewardAmount);

        // 6) finalize
        seller.transferOwnership(finalOwner);

        _allDeployed.push(address(seller));
        return address(seller);
    }
}