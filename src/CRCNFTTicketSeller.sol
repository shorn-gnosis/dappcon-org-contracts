// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "./interfaces/IHubV2.sol";
import "./interfaces/INameRegistry.sol";

contract CRCNFTTicketSeller {
    // Add the library methods for enumerable set
    using EnumerableSet for EnumerableSet.UintSet;

    // Declare a tickets set variable
    EnumerableSet.UintSet private tickets;
    // @todo add supplementary view function

    // Accounts which purchased tickets
    mapping(address => bool) private boughtTicket;

    address public owner;
    IERC721 public ticketNFT;
    uint256 public ticketPrice;
    uint256 public maxTickets;
    uint256 public ticketsSold;
    // State of the sale
    bool public isSaleActive;
    
    IHubV2 public constant HUB_V2 = IHubV2(address(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8));
    INameRegistry public constant NAME_REGISTRY = INameRegistry(address(0xA27566fD89162cC3D40Cb59c87AAaA49B85F3474));

    // ERROR
    error TicketSaleInactive();
    error NotOwner(address caller, address owner);
    error NotHuman();
    error NotHubSender();
    error NoTicketsAvailable();
    error InvalidCRCToken();
    error WrongPaidAmount(uint256 paidAmount, uint256 expectedAmount);
    error AlreadyBoughtTicket();
    error ArrayLengthMismatch();
    error EmptyArraysNotAllowed();
    error WrongNFTContract();

    // EVENTS
    event SaleOpened();
    event SaleClosed();
    event TicketPriceUpdated(uint256 newTicketPrice);
    event TicketMaxAmountUpdated(uint256 newTicketMaxAmount);
    event TicketSold(address indexed buyer, uint256 tokenId);
    event CRCRefunded(address indexed buyer, uint256 amount, string reason);

    modifier onlyOwner() {
        if(msg.sender != owner) revert NotOwner(msg.sender, owner);
        _;
    }


    // @todo withdraw accumulated CRC
    constructor(
        string memory _orgName,
        address _nftTicket,
        uint256 _ticketPrice,
        uint256 _maxTickets
    ) {
        owner = msg.sender;

        ticketNFT = IERC721(_nftTicket);
        // price in CRC
        ticketPrice = _ticketPrice;
        // max tickets available
        maxTickets = _maxTickets;
        
        // Register as organization if requested
        HUB_V2.registerOrganization(_orgName, 0);
    }
    // @todo test
    function updateMetadataDigest(bytes32 _metadataDigest) external {
        NAME_REGISTRY.updateMetadataDigest(_metadataDigest);
    }



    // Function to start and finish the sale
    function toggleSaleState() external onlyOwner {
        isSaleActive = !isSaleActive;

        if(isSaleActive) {
            emit SaleOpened();
        } else {
            emit SaleClosed();
        }
    }
    // Update ticket price
    function updateTicketPrice(uint256 _newPrice) external onlyOwner {
        ticketPrice = _newPrice;

        emit TicketPriceUpdated(_newPrice);
    }

    // Update max
    function updateTicketsMaxAmount(uint256 _newMaxAmount) external onlyOwner {
        maxTickets = _newMaxAmount;

        emit TicketMaxAmountUpdated(_newMaxAmount);
    }

    // @todo function to verify that the nft on the contract is accounted in the `tickets`

    function trust(address _trustedAddress, uint96 _expiry) external onlyOwner {
        // @dev according to the requirements only groups should be trusted
        // @todo check if the trusted account is a group
        HUB_V2.trust(_trustedAddress, _expiry);
    }

    function withdrawNFTs(uint256[] calldata tokenIds) external onlyOwner {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            // @todo check if it fails when there was no such token
            tickets.remove(tokenIds[i]);
            ticketNFT.safeTransferFrom(address(this), owner, tokenIds[i]);
        }
    }

    // @todo check if reentrancy is possible
    function onERC1155Received(
        address, // operator (unused)
        address from,
        uint256 id,
        uint256 value,
        bytes calldata // data (unused)
    ) external returns (bytes4) {
        // Ensure token ID is trusted
        if(!_isValidCRCId(id)) revert InvalidCRCToken();

        _checkAcceptance(from, value);

        // `from` is a recipient
        uint256 ticketId = _sellTicket(from);

        emit TicketSold(from, ticketId);

        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address, // operator (unused)
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata // data (unused)
    ) external returns (bytes4) {
        // Calculate total value sent and validate against ticket price
        uint256 totalValueSent = 0;
        for (uint256 i = 0; i < values.length; i++) {
            // Ensure each token ID is trusted
            if(!_isValidCRCId(ids[i])) revert InvalidCRCToken();       

            totalValueSent += values[i];
        }

        _checkAcceptance(from, totalValueSent);

        // Ensure arrays have same length
        if (ids.length != values.length) revert ArrayLengthMismatch();

        // Ensure arrays are not empty
        if (ids.length == 0) revert EmptyArraysNotAllowed();

        // `from` is a recipient
        uint256 ticketId = _sellTicket(from);

        emit TicketSold(from, ticketId);

        // Return the magic value to confirm receipt
        return this.onERC1155BatchReceived.selector;
    }

    // @dev in order to utilize this just send NFTs to this contract
    function onERC721Received(
        address,
        address from,
        uint256 tokenId,
        bytes calldata
    ) external returns (bytes4) {
        if(from != owner) revert NotOwner(from, owner); // only owner might add new tickets

        if(msg.sender != address(ticketNFT)) revert WrongNFTContract(); // @todo does not accept other nfts

        // Add ticket id to the set
        tickets.add(tokenId);

        // @todo add event regarding added nft

        return this.onERC721Received.selector;
    }
    // @todo update list of supported 
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return 
            interfaceId == this.supportsInterface.selector || // ERC165: 0x01ffc9a7
            interfaceId == this.onERC721Received.selector || // ERC721Receiver: 0x150b7a02
            interfaceId == this.onERC1155Received.selector || // ERC1155Receiver (single): 0x4e2312e0
            interfaceId == this.onERC1155BatchReceived.selector; // ERC1155Receiver (batch): 0xbc197c81
    }

    // INTERNAL FUNCTIONS

    // Validate that the token we get is trusted
    function _isValidCRCId(uint256 _id) private view returns(bool) {
        return HUB_V2.isTrusted(address(this), address(uint160(_id)));
    }

    function _checkAcceptance(address _from, uint256 _paidAmount) private {
        if(!isSaleActive) revert TicketSaleInactive();
        // Third party ERC1155 tokens are not accepted
        if (msg.sender != address(HUB_V2)) revert NotHubSender();

        // Purchaser should be a Circles human
        if(!HUB_V2.isHuman(_from)) revert NotHuman(); 

        // Ensure recipient doesn't already have a ticket
        if(boughtTicket[_from]) revert AlreadyBoughtTicket();

        if (ticketsSold >= maxTickets || tickets.length() == 0) revert NoTicketsAvailable();

        // Validate total sent value equals expected ticket price
        if (_paidAmount != ticketPrice) revert WrongPaidAmount(_paidAmount, ticketPrice);
    }

    function _sellTicket(address _recipient) private returns(uint256 soldTicketId) {   
        // Get the first item in the tickets list
        soldTicketId = tickets.at(0);
        tickets.remove(soldTicketId);
        ticketsSold++;
        boughtTicket[_recipient] = true;

        ticketNFT.safeTransferFrom(address(this), _recipient, soldTicketId);
    }
}