// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NFTSellerNoArgs.sol";

/* ========== FACTORY ========== */

// Parameters for NFT seller
struct NFTSellerParams {
    string orgName;
    address trustedAddr;
    uint256 offerStart;
    uint256 offerEnd;
    uint256 offerPrice;
    address requireTrustedBy;
    bool oncePerUser;
    bool oncePerDay;
    address nftContract;
}

/**
 * @title NFTSellerFactory
 * @notice Factory contract for creating NFT seller contracts
 * @dev Creates and configures NFTSellerNoArgs contracts
 */
contract NFTSellerFactory {
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
     * @dev One-click default NFT seller with predefined parameters
     */
    function createWithDefaultSeller() external returns (address) {
        // Hard-coded defaults
        NFTSellerParams memory p;
        p.orgName = "NFT Ticket Seller";
        p.trustedAddr = 0xc175a0c71f1eDA836ebbF3Ab0e32Fc8865FdEe91; // Default trusted address
        p.offerStart = block.timestamp;
        p.offerEnd = block.timestamp + (100 * 365 days);
        p.offerPrice = 5e18; // 5 CRC
        p.requireTrustedBy = address(0);
        p.oncePerUser = false;
        p.oncePerDay = false;
        p.nftContract = 0xa53A5773b9d4cE2cf5b42A7711239833b31ffc38; // Default NFT contract

        // Transfer ownership to the trusted address by default
        return _deploySeller(p, p.trustedAddr);
    }

    /**
     * @notice Create a custom NFT seller
     * @param p Parameters for the NFT seller
     */
    function createNFTSeller(NFTSellerParams calldata p) external returns (address) {
        // Copy fields to memory
        NFTSellerParams memory mem;
        mem.orgName = p.orgName;
        mem.trustedAddr = p.trustedAddr;
        mem.offerStart = (p.offerStart == 0) ? block.timestamp : p.offerStart;
        mem.offerEnd = (p.offerEnd == 0) ? (block.timestamp + (100 * 365 days)) : p.offerEnd;
        mem.offerPrice = p.offerPrice;
        mem.requireTrustedBy = p.requireTrustedBy;
        mem.oncePerUser = p.oncePerUser;
        mem.oncePerDay = p.oncePerDay;
        mem.nftContract = p.nftContract;

        // finalOwner => msg.sender
        return _deploySeller(mem, msg.sender);
    }

    /**
     * @dev Internal function to deploy and configure an NFT seller
     * @param s Parameters for the NFT seller
     * @param finalOwner Address that will own the deployed contract
     */
    function _deploySeller(NFTSellerParams memory s, address finalOwner) private returns (address) {
        NFTSellerNoArgs seller = new NFTSellerNoArgs();

        // 1) setHub => fixed
        seller.setHub(HARDCODED_HUB);

        // 2) register
        seller.registerOrg(s.orgName);

        // 3) trust => expiry => 100 years from now
        uint96 bigExpiry = uint96(block.timestamp + (100 * 365 days));
        seller.setTrustedAddress(s.trustedAddr, bigExpiry);

        // 4) configureOffer
        seller.configureOffer(s.offerStart, s.offerEnd, s.offerPrice, s.requireTrustedBy, s.oncePerUser, s.oncePerDay);

        // 5) configure NFT contract
        seller.configureNFTContract(s.nftContract);

        // 6) finalize
        seller.transferOwnership(finalOwner);

        _allDeployed.push(address(seller));
        return address(seller);
    }
}
