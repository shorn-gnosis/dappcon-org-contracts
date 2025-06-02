// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BackerNFTSeller.sol"; // Import the new seller contract

/* ========== FACTORY ========== */

// Parameters for the Backer NFT seller
struct BackerNFTSellerParams {
    string orgName;
    address trustedAddr;

    uint256 offerStart;
    uint256 offerEnd;
    uint256 offerPrice;
    address requireTrustedBy;
    bool oncePerUser;
    bool oncePerDay;

    address nftContract;
    address backerGroupAddress; // NEW: Backer group address parameter
}

/**
 * @title BackerNFTSellerFactory
 * @notice Factory contract for creating Backer NFT seller contracts
 * @dev Creates and configures BackerNFTSeller contracts
 */
contract BackerNFTSellerFactory {
    // Hardcode the hub
    address public constant HARDCODED_HUB = 0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8;

    address[] private _allDeployed;
    address public factoryOwner;

    event SellerCreated(address indexed sellerAddress, address indexed owner, BackerNFTSellerParams params);

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
     * @notice Create a custom Backer NFT seller
     * @param p Parameters for the Backer NFT seller
     */
    function createBackerNFTSeller(BackerNFTSellerParams calldata p) external returns (address) {
        // Copy fields to memory
        BackerNFTSellerParams memory mem;
        mem.orgName = p.orgName;
        mem.trustedAddr = p.trustedAddr;
        mem.offerStart = (p.offerStart == 0) ? block.timestamp : p.offerStart;
        mem.offerEnd = (p.offerEnd == 0) ? (block.timestamp + (100 * 365 days)) : p.offerEnd;
        mem.offerPrice = p.offerPrice;
        mem.requireTrustedBy = p.requireTrustedBy;
        mem.oncePerUser = p.oncePerUser;
        mem.oncePerDay = p.oncePerDay;
        mem.nftContract = p.nftContract;
        mem.backerGroupAddress = p.backerGroupAddress; // Copy new param

        // finalOwner => msg.sender
        return _deploySeller(mem, msg.sender);
    }

    /**
     * @dev Internal function to deploy and configure a Backer NFT seller
     * @param s Parameters for the Backer NFT seller
     * @param finalOwner Address that will own the deployed contract
     */
    function _deploySeller(BackerNFTSellerParams memory s, address finalOwner)
        private
        returns (address)
    {
        BackerNFTSeller seller = new BackerNFTSeller(); // Deploy the new seller type

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

        // 5) configure NFT contract
        seller.configureNFTContract(s.nftContract);

        // 6) configure Backer Group (NEW)
        if (s.backerGroupAddress != address(0)) {
            seller.configureBackerGroup(s.backerGroupAddress);
        }

        // 7) finalize ownership
        seller.transferOwnership(finalOwner);

        _allDeployed.push(address(seller));
        emit SellerCreated(address(seller), finalOwner, s);
        return address(seller);
    }
}
