// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import {IHubV2} from "src/interfaces/IHubV2.sol";

import "src/CRCNFTTicketSeller.sol";

import "test/mocks/MockNFT.sol";
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
        nftSellerContract = new CRCNFTTicketSeller(
            "TestOrd",
            address(nftTickets),
            1 ether,
            100
        );
        vm.prank(ADMIN);
        nftSellerContract.toggleSaleState();

        // Initialize test accounts with CRC balances
        _setMintTime(TEST_ACCOUNT_1);
        _setMintTime(TEST_ACCOUNT_2);
        _setCRCBalance(
            uint256(uint160(TEST_ACCOUNT_1)), TEST_ACCOUNT_1, HUB_V2.day(block.timestamp), uint192(CRC_AMOUNT * 2)
        );
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

    function testSendTicketsToTheContract() public {
        vm.prank(ADMIN);
        nftTickets.safeTransferFrom(ADMIN, address(nftSellerContract), 0);

        vm.prank(ADMIN);
        nftTickets.safeTransferFrom(ADMIN, address(nftSellerContract), 10);

        console.log(nftTickets.balanceOf(address(nftSellerContract)));
    }

    function test_BuyTicket() public {
        vm.prank(ADMIN);
        nftTickets.safeTransferFrom(ADMIN, address(nftSellerContract), 10);

        console.log(
            IERC1155(address(HUB_V2)).balanceOf(TEST_ACCOUNT_1, uint256(uint160(TEST_ACCOUNT_1)))
        );
        vm.prank(ADMIN);
        nftSellerContract.trust(TEST_ACCOUNT_1, uint96(block.timestamp + 365 days));

        vm.prank(TEST_ACCOUNT_1);
        IERC1155(address(HUB_V2)).safeTransferFrom(TEST_ACCOUNT_1, address(nftSellerContract), uint256(uint160(TEST_ACCOUNT_1)), 1 ether, "");

        console.log("Amount of purchased tickets: ", nftTickets.balanceOf(TEST_ACCOUNT_1));

        console.log(
            IERC1155(address(HUB_V2)).balanceOf(TEST_ACCOUNT_1, uint256(uint160(TEST_ACCOUNT_1)))
        );

    }
}
