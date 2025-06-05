// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/CirclesPixelGrid.sol";
import "./mocks/MockHub.sol";

contract CirclesPixelGridTest is Test {
    CirclesPixelGrid internal pixelGridContract;
    MockHub internal hubMock;

    address internal owner;
    address internal user1;
    address internal user2;

    uint256 internal constant CRC_TOKEN_ID = 12345; // Example CRC Token ID for testing
    uint256 internal constant PIXEL_PRICE = 100 * 1e18;
    uint256 internal constant GRID_SIZE = 100;

    function setUp() public {
        // Create users
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy Mock Hub
        hubMock = new MockHub();

        // Deploy Pixel Grid Contract (as owner)
        vm.prank(owner);
        pixelGridContract = new CirclesPixelGrid("Test Org", address(hubMock));

        // Mint some mock CRC for user1
        hubMock.mint(user1, CRC_TOKEN_ID, 1000 * 1e18); // Give user1 1000 CRC
    }

    // --- Test Constructor ---

    function test_Constructor_SetsState() public {
        assertEq(pixelGridContract.owner(), owner);
        assertEq(pixelGridContract.hubAddress(), address(hubMock));
        assertEq(pixelGridContract.orgName(), "Test Org");
        assertTrue(pixelGridContract.isRegistered(), "Org should be registered via mock");
        assertEq(pixelGridContract.pixelsSold(), 0);
    }

    // --- Test Purchase Success ---

    function test_PurchasePixelSuccess() public {
        // Arrange
        uint256 x = 10;
        uint256 y = 20;
        uint256 pixelId = y * GRID_SIZE + x;
        uint24 color = 0xFF0000; // Red
        string memory linkUrl = "https://example.com";
        bytes memory data = abi.encode(x, y, color, linkUrl);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit CirclesPixelGrid.PixelPurchased(user1, pixelId, x, y, color, linkUrl);

        // Act: Simulate user1 sending CRC via the Hub to the contract
        // We need to change the msg.sender for the hubMock call to simulate it coming from the hub
        vm.prank(address(hubMock));
        pixelGridContract.onERC1155Received(user1, user1, CRC_TOKEN_ID, PIXEL_PRICE, data);

        // Assert State Changes
        CirclesPixelGrid.PixelData memory pixelData = pixelGridContract.getPixelData(x, y);
        assertEq(pixelData.owner, user1, "Pixel owner should be user1");
        assertEq(pixelData.color, color, "Pixel color mismatch");
        assertEq(pixelData.linkUrl, linkUrl, "Pixel linkUrl mismatch");

        assertEq(pixelGridContract.userPixelCount(user1), 1, "User1 pixel count should be 1");
        assertEq(pixelGridContract.pixelsSold(), 1, "Total pixels sold should be 1");

        // Assert CRC transfer to owner
        assertEq(
            hubMock.balances(address(pixelGridContract), CRC_TOKEN_ID),
            0,
            "Contract CRC balance should be 0 after forwarding"
        );
        assertEq(hubMock.balances(owner, CRC_TOKEN_ID), PIXEL_PRICE, "Owner should have received pixel price");
    }

    function test_PurchasePixelSuccess_OverpaymentRefund() public {
        // Arrange
        uint256 x = 5;
        uint256 y = 5;
        uint256 pixelId = y * GRID_SIZE + x;
        uint24 color = 0x00FF00; // Green
        string memory linkUrl = "";
        bytes memory data = abi.encode(x, y, color, linkUrl);
        uint256 paymentAmount = PIXEL_PRICE + 50 * 1e18; // Overpay by 50 CRC

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit CirclesPixelGrid.PixelPurchased(user1, pixelId, x, y, color, linkUrl);

        // Act
        vm.prank(address(hubMock));
        pixelGridContract.onERC1155Received(user1, user1, CRC_TOKEN_ID, paymentAmount, data);

        // Assert State Changes
        CirclesPixelGrid.PixelData memory pixelData = pixelGridContract.getPixelData(x, y);
        assertEq(pixelData.owner, user1);
        assertEq(pixelGridContract.userPixelCount(user1), 1);
        assertEq(pixelGridContract.pixelsSold(), 1);

        // Assert CRC transfers
        assertEq(hubMock.balances(address(pixelGridContract), CRC_TOKEN_ID), 0, "Contract CRC balance should be 0");
        assertEq(hubMock.balances(owner, CRC_TOKEN_ID), PIXEL_PRICE, "Owner received price");
        // Check if user1 got the refund (initial 1000 - paymentAmount + refundAmount)
        // Note: MockHub doesn't track initial balance decrease, so we check final balance vs expected refund
        assertEq(
            hubMock.balances(user1, CRC_TOKEN_ID), (1000 * 1e18) - PIXEL_PRICE, "User1 balance should reflect refund"
        );
        // Alternative check: Check the refund amount was transferred back
        // This requires modifying MockHub or using cheatcodes to track transfers,
        // or checking the final balance carefully. The balance check above assumes
        // the mock hub correctly handled the refund transfer back to user1.
    }

    // --- Test Purchase Failures ---

    function test_PurchasePixelFail_InsufficientCRC() public {
        // Arrange
        uint256 x = 1;
        uint256 y = 1;
        uint24 color = 0x0000FF; // Blue
        string memory linkUrl = "";
        bytes memory data = abi.encode(x, y, color, linkUrl);
        uint256 insufficientAmount = PIXEL_PRICE - 1 wei;

        // Expect refund event
        vm.expectEmit(true, false, false, true); // buyer indexed
        emit CirclesPixelGrid.CRCRefunded(user1, insufficientAmount, "Insufficient CRC");

        // Act: Simulate transfer with insufficient amount
        vm.prank(address(hubMock));
        pixelGridContract.onERC1155Received(user1, user1, CRC_TOKEN_ID, insufficientAmount, data);

        // Assert: Check pixel was not assigned and state not changed
        CirclesPixelGrid.PixelData memory pixelData = pixelGridContract.getPixelData(x, y);
        assertEq(pixelData.owner, address(0), "Pixel should not be owned");
        assertEq(pixelGridContract.userPixelCount(user1), 0, "User pixel count should be 0");
        assertEq(pixelGridContract.pixelsSold(), 0, "Pixels sold should be 0");
        // Assert refund occurred (user balance should be unchanged as refund matches insufficient payment)
        assertEq(
            hubMock.balances(user1, CRC_TOKEN_ID), 1000 * 1e18, "User balance should be initial amount after refund"
        );
        assertEq(hubMock.balances(address(pixelGridContract), CRC_TOKEN_ID), 0, "Contract balance should be 0");
        assertEq(hubMock.balances(owner, CRC_TOKEN_ID), 0, "Owner balance should be 0");
    }

    function test_PurchasePixelFail_MaxPixelsReached() public {
        // Arrange: Buy max pixels first
        uint24 color = 0x112233;
        string memory linkUrl = "max";
        for (uint256 i = 0; i < pixelGridContract.MAX_PIXELS_PER_USER(); i++) {
            bytes memory data = abi.encode(i, 0, color, linkUrl); // Buy pixels (0,0) to (9,0)
            vm.prank(address(hubMock));
            pixelGridContract.onERC1155Received(user1, user1, CRC_TOKEN_ID, PIXEL_PRICE, data);
        }
        assertEq(pixelGridContract.userPixelCount(user1), pixelGridContract.MAX_PIXELS_PER_USER());

        // Attempt to buy one more pixel
        uint256 x = pixelGridContract.MAX_PIXELS_PER_USER(); // (10, 0)
        uint256 y = 0;
        bytes memory dataFail = abi.encode(x, y, color, linkUrl);

        // Expect refund event
        vm.expectEmit(true, false, false, true);
        emit CirclesPixelGrid.CRCRefunded(user1, PIXEL_PRICE, "Max pixels reached");

        // Act
        vm.prank(address(hubMock));
        pixelGridContract.onERC1155Received(user1, user1, CRC_TOKEN_ID, PIXEL_PRICE, dataFail);

        // Assert: Check pixel was not assigned
        CirclesPixelGrid.PixelData memory pixelData = pixelGridContract.getPixelData(x, y);
        assertEq(pixelData.owner, address(0));
        assertEq(pixelGridContract.pixelsSold(), pixelGridContract.MAX_PIXELS_PER_USER()); // Should not have increased
    }

    function test_PurchasePixelFail_PixelOwned() public {
        // Arrange: Buy a pixel first
        uint256 x = 2;
        uint256 y = 2;
        uint24 color = 0x445566;
        string memory linkUrl = "owned";
        bytes memory data = abi.encode(x, y, color, linkUrl);
        vm.prank(address(hubMock));
        pixelGridContract.onERC1155Received(user1, user1, CRC_TOKEN_ID, PIXEL_PRICE, data);

        // Mint CRC for user2
        hubMock.mint(user2, CRC_TOKEN_ID, PIXEL_PRICE);

        // Attempt to buy the same pixel with user2
        // Expect refund event
        vm.expectEmit(true, false, false, true);
        emit CirclesPixelGrid.CRCRefunded(user2, PIXEL_PRICE, "Pixel already owned");

        // Act
        vm.prank(address(hubMock));
        pixelGridContract.onERC1155Received(user2, user2, CRC_TOKEN_ID, PIXEL_PRICE, data); // Use same data

        // Assert: Check pixel owner is still user1
        CirclesPixelGrid.PixelData memory pixelData = pixelGridContract.getPixelData(x, y);
        assertEq(pixelData.owner, user1);
        assertEq(pixelGridContract.pixelsSold(), 1); // Should still be 1
        assertEq(pixelGridContract.userPixelCount(user2), 0);
    }

    function test_PurchasePixelFail_InvalidCoordinates() public {
        // Arrange
        uint256 x = GRID_SIZE; // Invalid coordinate (100)
        uint256 y = 0;
        uint24 color = 0x778899;
        string memory linkUrl = "invalid";
        bytes memory data = abi.encode(x, y, color, linkUrl);

        // Act & Assert: Expect revert due to coordinate check before refund logic
        vm.prank(address(hubMock));
        vm.expectRevert("PixelGrid: Invalid coordinates");
        pixelGridContract.onERC1155Received(user1, user1, CRC_TOKEN_ID, PIXEL_PRICE, data);
    }

    function test_PurchasePixelFail_NotFromHub() public {
        // Arrange
        uint256 x = 3;
        uint256 y = 3;
        uint24 color = 0xAABBCC;
        string memory linkUrl = "direct";
        bytes memory data = abi.encode(x, y, color, linkUrl);

        // Act & Assert: Call directly from user1 (not Hub) - should revert
        vm.prank(user1); // Prank as user1
        vm.expectRevert("PixelGrid: Not from Hub");
        pixelGridContract.onERC1155Received(user1, user1, CRC_TOKEN_ID, PIXEL_PRICE, data);
    }

    // TODO: test_PurchasePixelFail_OrgNotRegistered (Difficult to test reliably with current mock, requires deploying contract without calling _registerOrg or mock returning false)

    // --- Test Update ---

    function test_UpdatePixelDataSuccess() public {
        // Arrange: Buy a pixel first
        uint256 x = 7;
        uint256 y = 8;
        uint256 pixelId = y * GRID_SIZE + x;
        uint24 initialColor = 0xCCCCCC;
        string memory initialLink = "initial.com";
        bytes memory purchaseData = abi.encode(x, y, initialColor, initialLink);
        vm.prank(address(hubMock));
        pixelGridContract.onERC1155Received(user1, user1, CRC_TOKEN_ID, PIXEL_PRICE, purchaseData);

        // New data
        uint24 newColor = 0xABCDEF;
        string memory newLink = "updated.org";

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit CirclesPixelGrid.PixelUpdated(user1, pixelId, x, y, newColor, newLink);

        // Act: Update data as user1
        vm.prank(user1);
        pixelGridContract.updatePixelData(x, y, newColor, newLink);

        // Assert: Check pixel data was updated
        CirclesPixelGrid.PixelData memory pixelData = pixelGridContract.getPixelData(x, y);
        assertEq(pixelData.owner, user1); // Owner should remain the same
        assertEq(pixelData.color, newColor, "Color should be updated");
        assertEq(pixelData.linkUrl, newLink, "Link URL should be updated");
    }

    function test_UpdatePixelDataFail_NotOwner() public {
        // Arrange: Buy a pixel first with user1
        uint256 x = 7;
        uint256 y = 8;
        uint24 initialColor = 0xCCCCCC;
        string memory initialLink = "initial.com";
        bytes memory purchaseData = abi.encode(x, y, initialColor, initialLink);
        vm.prank(address(hubMock));
        pixelGridContract.onERC1155Received(user1, user1, CRC_TOKEN_ID, PIXEL_PRICE, purchaseData);

        // New data
        uint24 newColor = 0xABCDEF;
        string memory newLink = "updated.org";

        // Act & Assert: Attempt update as user2 (not owner) - should revert
        vm.prank(user2);
        vm.expectRevert("PixelGrid: Not pixel owner");
        pixelGridContract.updatePixelData(x, y, newColor, newLink);

        // Assert: Check data was NOT updated
        CirclesPixelGrid.PixelData memory pixelData = pixelGridContract.getPixelData(x, y);
        assertEq(pixelData.color, initialColor);
        assertEq(pixelData.linkUrl, initialLink);
    }

    function test_UpdatePixelDataFail_InvalidCoordinates() public {
        // Arrange: Buy a pixel first
        uint256 x = 7;
        uint256 y = 8;
        uint24 initialColor = 0xCCCCCC;
        string memory initialLink = "initial.com";
        bytes memory purchaseData = abi.encode(x, y, initialColor, initialLink);
        vm.prank(address(hubMock));
        pixelGridContract.onERC1155Received(user1, user1, CRC_TOKEN_ID, PIXEL_PRICE, purchaseData);

        // New data
        uint24 newColor = 0xABCDEF;
        string memory newLink = "updated.org";

        // Act & Assert: Attempt update with invalid coordinates
        vm.prank(user1);
        vm.expectRevert("PixelGrid: Invalid coordinates");
        pixelGridContract.updatePixelData(GRID_SIZE, y, newColor, newLink); // Invalid x
    }

    // --- Test Views ---

    function test_GetPixelData_Unowned() public {
        // Arrange: No pixel purchased at (0,0)
        uint256 x = 0;
        uint256 y = 0;

        // Act
        CirclesPixelGrid.PixelData memory pixelData = pixelGridContract.getPixelData(x, y);

        // Assert
        assertEq(pixelData.owner, address(0), "Owner should be zero address for unowned pixel");
        assertEq(pixelData.color, 0, "Color should be zero for unowned pixel");
        assertEq(pixelData.linkUrl, "", "Link URL should be empty for unowned pixel");
    }

    function test_GetUserPixelCount_Zero() public {
        // Arrange: No pixels purchased by user2
        // Act
        uint256 count = pixelGridContract.getUserPixelCount(user2);

        // Assert
        assertEq(count, 0, "Pixel count for user2 should be zero initially");
    }
}
