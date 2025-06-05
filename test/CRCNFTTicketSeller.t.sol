// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import {IHubV2} from "src/interfaces/IHubV2.sol";

import "src/CRCNFTTicketSeller.sol";

import "test/mocks/MockNFT.sol";
// @todo improve tests, separate generated tests from selfcoded
/**
 * @title CRCNFTTicketSellerTest
 */

contract CRCNFTTicketSellerTest is Test {
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------
    uint256 public constant USDC_START_AMOUNT = 100e6; // 100 USDC
    uint256 public constant BACKING_ASSET_DEAL_AMOUNT = 0.03 ether;
    uint256 public constant YEAR = 365 days;
    uint256 public constant MAX_DELTA = 3e10;
    uint256 public constant SWAP_FEE = 0.03 ether;
    int256 public constant INITIAL_FEED_PRICE = 10 ether;

    // Storage slots
    uint256 public constant ORDER_FILLED_SLOT = 2;
    uint256 public constant DISCOUNTED_BALANCES_SLOT = 17;
    uint256 public constant MINT_TIMES_SLOT = 21;

    // Standard addresses
    IHubV2 public constant HUB_V2 = IHubV2(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8);

    // -------------------------------------------------------------------------
    // State Variables
    // -------------------------------------------------------------------------
    CRCNFTTicketSeller public nftSellerContract;
    MockNFT public nftTickets;

    // -------------------------------------------------------------------------
    // State Variables
    // -------------------------------------------------------------------------

    address internal ADMIN = makeAddr("admin");
    address internal TEST_ACCOUNT_1 = makeAddr("alice");
    address internal TEST_ACCOUNT_2 = makeAddr("bob");

    uint256 internal CRC_AMOUNT;
    uint64 internal TODAY;

    // Gnosis fork ID
    uint256 internal gnosisFork;

    // The CowSwap order uid for the test instance
    bytes public uid;

    // -------------------------------------------------------------------------
    // Setup
    // -------------------------------------------------------------------------

    function setUp() public {
        // Fork from Gnosis
        gnosisFork = vm.createFork(vm.envString("GNOSIS_RPC"));
        vm.selectFork(gnosisFork);
        vm.deal(ADMIN, 1 ether);

        CRC_AMOUNT = 48e18;

        TODAY = HUB_V2.day(block.timestamp);

        vm.prank(ADMIN);
        nftTickets = new MockNFT("Tickets", "DT");

        vm.prank(ADMIN);
        nftSellerContract = new CRCNFTTicketSeller("TestOrd", address(nftTickets), 1 ether, 100);
        vm.prank(ADMIN);
        nftSellerContract.toggleSaleState();

        // Initialize test accounts with CRC balances
        _setMintTime(TEST_ACCOUNT_1);
        _setMintTime(TEST_ACCOUNT_2);
        // Mint personal CRC to TEST_ACCOUNT_1
        _setCRCBalance(
            uint256(uint160(TEST_ACCOUNT_1)), TEST_ACCOUNT_1, HUB_V2.day(block.timestamp), uint192(CRC_AMOUNT * 2)
        );
        // Mint TEST_ACCOUNT_2 CRC to TEST_ACCOUNT_1
        _setCRCBalance(
            uint256(uint160(TEST_ACCOUNT_2)), TEST_ACCOUNT_1, HUB_V2.day(block.timestamp), uint192(CRC_AMOUNT * 2)
        );
        // Mint personal CRC to TEST_ACCOUNT_2
        _setCRCBalance(
            uint256(uint160(TEST_ACCOUNT_2)), TEST_ACCOUNT_2, HUB_V2.day(block.timestamp), uint192(CRC_AMOUNT * 2)
        );
    }

    // -------------------------------------------------------------------------
    // Hub-Related Helpers
    // -------------------------------------------------------------------------

    /**
     * @notice Sets Hub mint times for account
     * @param account The account to set mint time for
     */
    function _setMintTime(address account) internal {
        bytes32 accountSlot = keccak256(abi.encodePacked(uint256(uint160(account)), MINT_TIMES_SLOT));
        uint256 mintTime = block.timestamp << 160;
        vm.store(address(HUB_V2), accountSlot, bytes32(mintTime));
    }

    /**
     * @notice Sets Hub ERC1155 balance of id for account
     * @param id The token ID
     * @param account The account to set balance for
     * @param lastUpdatedDay The last updated day
     * @param balance The balance to set
     */
    function _setCRCBalance(uint256 id, address account, uint64 lastUpdatedDay, uint192 balance) internal {
        bytes32 idSlot = keccak256(abi.encodePacked(id, DISCOUNTED_BALANCES_SLOT));
        bytes32 accountSlot = keccak256(abi.encodePacked(uint256(uint160(account)), idSlot));
        uint256 discountedBalance = (uint256(lastUpdatedDay) << 192) + balance;
        vm.store(address(HUB_V2), accountSlot, bytes32(discountedBalance));
    }
    // @todo improve

    function test_SendTicketsToTheContract() public {
        vm.prank(ADMIN);
        nftTickets.safeTransferFrom(ADMIN, address(nftSellerContract), 0);

        vm.prank(ADMIN);
        nftTickets.safeTransferFrom(ADMIN, address(nftSellerContract), 10);
    }

    function test_WithdrawNotAccountedNFT() public {
        nftTickets.unsafeNFTMint(address(nftSellerContract), 999);

        vm.prank(ADMIN);
        uint256[] memory ticketsToWithdraw = new uint256[](1);
        ticketsToWithdraw[0] = 999;
        nftSellerContract.withdrawNFTs(ticketsToWithdraw);
    }

    // @todo improve
    function test_BuyTicket() public {
        vm.prank(ADMIN);
        nftTickets.safeTransferFrom(ADMIN, address(nftSellerContract), 10);

        vm.prank(ADMIN);
        nftSellerContract.trust(TEST_ACCOUNT_1, uint96(block.timestamp + 365 days));

        vm.prank(TEST_ACCOUNT_1);
        IERC1155(address(HUB_V2)).safeTransferFrom(
            TEST_ACCOUNT_1, address(nftSellerContract), uint256(uint160(TEST_ACCOUNT_1)), 1 ether, ""
        );

        uint256[] memory crcIds = new uint256[](1);
        crcIds[0] = uint256(uint160(TEST_ACCOUNT_1));
        uint256[] memory crcAmounts = new uint256[](1);
        crcAmounts[0] =
            IERC1155(address(HUB_V2)).balanceOf(address(nftSellerContract), uint256(uint160(TEST_ACCOUNT_1)));

        vm.prank(ADMIN);
        nftSellerContract.withdrawERC1155Tokens(address(HUB_V2), crcIds, crcAmounts);
    }

    // Generated tests

    function test_RevertWhenSaleInactive() public {
        // First add a ticket to the contract
        vm.prank(ADMIN);
        nftTickets.safeTransferFrom(ADMIN, address(nftSellerContract), 10);

        // Toggle sale to inactive
        vm.prank(ADMIN);
        nftSellerContract.toggleSaleState();

        // Trust the buyer
        vm.prank(ADMIN);
        nftSellerContract.trust(TEST_ACCOUNT_1, uint96(block.timestamp + 365 days));

        // Try to buy when sale is inactive
        vm.prank(TEST_ACCOUNT_1);
        vm.expectRevert(CRCNFTTicketSeller.TicketSaleInactive.selector);
        IERC1155(address(HUB_V2)).safeTransferFrom(
            TEST_ACCOUNT_1, address(nftSellerContract), uint256(uint160(TEST_ACCOUNT_1)), 1 ether, ""
        );
    }

    function test_RevertWhenAlreadyBoughtTicket() public {
        // Add tickets
        vm.prank(ADMIN);
        nftTickets.safeTransferFrom(ADMIN, address(nftSellerContract), 10);
        vm.prank(ADMIN);
        nftTickets.safeTransferFrom(ADMIN, address(nftSellerContract), 11);

        // Trust buyer
        vm.prank(ADMIN);
        nftSellerContract.trust(TEST_ACCOUNT_1, uint96(block.timestamp + 365 days));

        // First purchase should succeed
        vm.prank(TEST_ACCOUNT_1);
        IERC1155(address(HUB_V2)).safeTransferFrom(
            TEST_ACCOUNT_1, address(nftSellerContract), uint256(uint160(TEST_ACCOUNT_1)), 1 ether, ""
        );

        // Second purchase should fail
        vm.prank(TEST_ACCOUNT_1);
        vm.expectRevert(CRCNFTTicketSeller.AlreadyBoughtTicket.selector);
        IERC1155(address(HUB_V2)).safeTransferFrom(
            TEST_ACCOUNT_1, address(nftSellerContract), uint256(uint160(TEST_ACCOUNT_1)), 1 ether, ""
        );
    }

    function test_RevertWhenWrongPaymentAmount() public {
        // Add ticket
        vm.prank(ADMIN);
        nftTickets.safeTransferFrom(ADMIN, address(nftSellerContract), 10);

        // Trust buyer
        vm.prank(ADMIN);
        nftSellerContract.trust(TEST_ACCOUNT_1, uint96(block.timestamp + 365 days));

        // Try to buy with wrong amount (0.5 ether instead of 1 ether)
        vm.prank(TEST_ACCOUNT_1);
        vm.expectRevert(abi.encodeWithSelector(CRCNFTTicketSeller.WrongPaidAmount.selector, 0.5 ether, 1 ether));
        IERC1155(address(HUB_V2)).safeTransferFrom(
            TEST_ACCOUNT_1, address(nftSellerContract), uint256(uint160(TEST_ACCOUNT_1)), 0.5 ether, ""
        );
    }

    function test_RevertWhenNoTicketsAvailable() public {
        // Don't add any tickets

        // Trust buyer
        vm.prank(ADMIN);
        nftSellerContract.trust(TEST_ACCOUNT_1, uint96(block.timestamp + 365 days));

        // Try to buy when no tickets available
        vm.prank(TEST_ACCOUNT_1);
        vm.expectRevert(CRCNFTTicketSeller.NoTicketsAvailable.selector);
        IERC1155(address(HUB_V2)).safeTransferFrom(
            TEST_ACCOUNT_1, address(nftSellerContract), uint256(uint160(TEST_ACCOUNT_1)), 1 ether, ""
        );
    }

    function test_UpdateTicketPrice() public {
        uint256 newPrice = 2 ether;

        // Update price
        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit CRCNFTTicketSeller.TicketPriceUpdated(newPrice);
        nftSellerContract.updateTicketPrice(newPrice);

        assertEq(nftSellerContract.ticketPrice(), newPrice);

        // Test buying with new price
        vm.prank(ADMIN);
        nftTickets.safeTransferFrom(ADMIN, address(nftSellerContract), 10);

        vm.prank(ADMIN);
        nftSellerContract.trust(TEST_ACCOUNT_1, uint96(block.timestamp + 365 days));

        // Should fail with old price
        vm.prank(TEST_ACCOUNT_1);
        vm.expectRevert(abi.encodeWithSelector(CRCNFTTicketSeller.WrongPaidAmount.selector, 1 ether, 2 ether));
        IERC1155(address(HUB_V2)).safeTransferFrom(
            TEST_ACCOUNT_1, address(nftSellerContract), uint256(uint160(TEST_ACCOUNT_1)), 1 ether, ""
        );

        // Should succeed with new price
        vm.prank(TEST_ACCOUNT_1);
        IERC1155(address(HUB_V2)).safeTransferFrom(
            TEST_ACCOUNT_1, address(nftSellerContract), uint256(uint160(TEST_ACCOUNT_1)), 2 ether, ""
        );
    }

    function test_UpdateMaxTickets() public {
        uint256 newMax = 50;

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit CRCNFTTicketSeller.TicketMaxAmountUpdated(newMax);
        nftSellerContract.updateTicketsMaxAmount(newMax);

        assertEq(nftSellerContract.maxTickets(), newMax);
    }

    function test_OnlyOwnerCanToggleSale() public {
        vm.prank(TEST_ACCOUNT_1);
        vm.expectRevert(abi.encodeWithSelector(CRCNFTTicketSeller.NotOwner.selector, TEST_ACCOUNT_1, ADMIN));
        nftSellerContract.toggleSaleState();
    }

    function test_OnlyOwnerCanUpdatePrice() public {
        vm.prank(TEST_ACCOUNT_1);
        vm.expectRevert(abi.encodeWithSelector(CRCNFTTicketSeller.NotOwner.selector, TEST_ACCOUNT_1, ADMIN));
        nftSellerContract.updateTicketPrice(2 ether);
    }

    function test_OnlyOwnerCanWithdrawNFTs() public {
        // Add ticket first
        vm.prank(ADMIN);
        nftTickets.safeTransferFrom(ADMIN, address(nftSellerContract), 10);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 10;

        vm.prank(TEST_ACCOUNT_1);
        vm.expectRevert(abi.encodeWithSelector(CRCNFTTicketSeller.NotOwner.selector, TEST_ACCOUNT_1, ADMIN));
        nftSellerContract.withdrawNFTs(tokenIds);
    }

    function test_WithdrawNFTs() public {
        // Add multiple tickets
        vm.prank(ADMIN);
        nftTickets.safeTransferFrom(ADMIN, address(nftSellerContract), 10);
        vm.prank(ADMIN);
        nftTickets.safeTransferFrom(ADMIN, address(nftSellerContract), 11);
        vm.prank(ADMIN);
        nftTickets.safeTransferFrom(ADMIN, address(nftSellerContract), 12);

        assertEq(nftTickets.balanceOf(address(nftSellerContract)), 3);
        assertEq(nftTickets.balanceOf(ADMIN), 97); // Started with 100

        // Withdraw specific NFTs
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 10;
        tokenIds[1] = 12;

        vm.prank(ADMIN);
        nftSellerContract.withdrawNFTs(tokenIds);

        assertEq(nftTickets.balanceOf(address(nftSellerContract)), 1);
        assertEq(nftTickets.balanceOf(ADMIN), 99);
        assertEq(nftTickets.ownerOf(11), address(nftSellerContract));
        assertEq(nftTickets.ownerOf(10), ADMIN);
        assertEq(nftTickets.ownerOf(12), ADMIN);
    }

    function test_BatchReceiveWithMultipleTokens() public {
        // Add ticket
        vm.prank(ADMIN);
        nftTickets.safeTransferFrom(ADMIN, address(nftSellerContract), 10);

        // Trust both accounts
        vm.prank(ADMIN);
        nftSellerContract.trust(TEST_ACCOUNT_1, uint96(block.timestamp + 365 days));
        vm.prank(ADMIN);
        nftSellerContract.trust(TEST_ACCOUNT_2, uint96(block.timestamp + 365 days));

        // Prepare batch transfer - multiple token IDs that sum to ticket price
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = uint256(uint160(TEST_ACCOUNT_1));
        ids[1] = uint256(uint160(TEST_ACCOUNT_2));
        amounts[0] = 0.6 ether;
        amounts[1] = 0.4 ether;

        vm.prank(TEST_ACCOUNT_1);
        IERC1155(address(HUB_V2)).safeBatchTransferFrom(TEST_ACCOUNT_1, address(nftSellerContract), ids, amounts, "");

        assertEq(nftTickets.balanceOf(TEST_ACCOUNT_1), 1);
    }

    function test_RevertBatchReceiveWithWrongTotal() public {
        // Add ticket
        vm.prank(ADMIN);
        nftTickets.safeTransferFrom(ADMIN, address(nftSellerContract), 10);

        // Trust accounts
        vm.prank(ADMIN);
        nftSellerContract.trust(TEST_ACCOUNT_1, uint96(block.timestamp + 365 days));
        vm.prank(ADMIN);
        nftSellerContract.trust(TEST_ACCOUNT_2, uint96(block.timestamp + 365 days));

        // Prepare batch transfer with wrong total
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = uint256(uint160(TEST_ACCOUNT_1));
        ids[1] = uint256(uint160(TEST_ACCOUNT_2));
        amounts[0] = 0.6 ether;
        amounts[1] = 0.3 ether; // Total is 0.9 ether, not 1 ether

        vm.prank(TEST_ACCOUNT_1);
        vm.expectRevert(abi.encodeWithSelector(CRCNFTTicketSeller.WrongPaidAmount.selector, 0.9 ether, 1 ether));
        IERC1155(address(HUB_V2)).safeBatchTransferFrom(TEST_ACCOUNT_1, address(nftSellerContract), ids, amounts, "");
    }

    function test_RevertOnReceivingWrongNFT() public {
        // Create another NFT contract
        vm.prank(ADMIN);
        MockNFT anotherNFT = new MockNFT("Another", "ANT");

        // Try to send wrong NFT to the contract
        vm.prank(ADMIN);
        vm.expectRevert(CRCNFTTicketSeller.WrongNFTContract.selector);
        anotherNFT.safeTransferFrom(ADMIN, address(nftSellerContract), 0);
    }

    function test_OnlyOwnerCanSendNFTs() public {
        // Mint NFT to TEST_ACCOUNT_1
        vm.prank(ADMIN);
        nftTickets.safeTransferFrom(ADMIN, TEST_ACCOUNT_1, 20);

        // Try to send NFT from non-owner
        vm.prank(TEST_ACCOUNT_1);
        vm.expectRevert(abi.encodeWithSelector(CRCNFTTicketSeller.NotOwner.selector, TEST_ACCOUNT_1, ADMIN));
        nftTickets.safeTransferFrom(TEST_ACCOUNT_1, address(nftSellerContract), 20);
    }

    function test_SupportsInterface() public view {
        // ERC165
        assertTrue(nftSellerContract.supportsInterface(0x01ffc9a7));
        // ERC721Receiver
        assertTrue(nftSellerContract.supportsInterface(0x150b7a02));
        // ERC1155Receiver single
        assertTrue(nftSellerContract.supportsInterface(0xf23a6e61));
        // ERC1155Receiver batch
        assertTrue(nftSellerContract.supportsInterface(0xbc197c81));
        // Random interface should return false
        assertFalse(nftSellerContract.supportsInterface(0x12345678));
    }

    function test_MultipleBuyersCanPurchase() public {
        // Add multiple tickets
        vm.prank(ADMIN);
        nftTickets.safeTransferFrom(ADMIN, address(nftSellerContract), 10);
        vm.prank(ADMIN);
        nftTickets.safeTransferFrom(ADMIN, address(nftSellerContract), 11);

        // Trust both buyers
        vm.prank(ADMIN);
        nftSellerContract.trust(TEST_ACCOUNT_1, uint96(block.timestamp + 365 days));
        vm.prank(ADMIN);
        nftSellerContract.trust(TEST_ACCOUNT_2, uint96(block.timestamp + 365 days));

        // First buyer purchases
        vm.prank(TEST_ACCOUNT_1);
        IERC1155(address(HUB_V2)).safeTransferFrom(
            TEST_ACCOUNT_1, address(nftSellerContract), uint256(uint160(TEST_ACCOUNT_1)), 1 ether, ""
        );

        // Second buyer purchases
        vm.prank(TEST_ACCOUNT_2);
        IERC1155(address(HUB_V2)).safeTransferFrom(
            TEST_ACCOUNT_2, address(nftSellerContract), uint256(uint160(TEST_ACCOUNT_2)), 1 ether, ""
        );

        assertEq(nftTickets.balanceOf(TEST_ACCOUNT_1), 1);
        assertEq(nftTickets.balanceOf(TEST_ACCOUNT_2), 1);
        assertEq(nftSellerContract.ticketsSold(), 2);
    }

    function test_UpdateMetadataDigest() public {
        bytes32 newDigest = keccak256("new metadata");

        // Only owner can update
        vm.prank(TEST_ACCOUNT_1);
        vm.expectRevert();
        nftSellerContract.updateMetadataDigest(newDigest);

        // Owner updates successfully
        vm.prank(ADMIN);
        nftSellerContract.updateMetadataDigest(newDigest);
    }

    function test_EmitEventsOnSaleToggle() public {
        // Toggle to inactive (was active in setUp)
        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit CRCNFTTicketSeller.SaleClosed();
        nftSellerContract.toggleSaleState();

        assertFalse(nftSellerContract.isSaleActive());

        // Toggle back to active
        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit CRCNFTTicketSeller.SaleOpened();
        nftSellerContract.toggleSaleState();

        assertTrue(nftSellerContract.isSaleActive());
    }
}
