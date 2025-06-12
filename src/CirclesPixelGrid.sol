// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/console.sol"; // For debugging during development

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

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC1155 {
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external;
}

interface IHub {
    function registerOrganization(string calldata _name, bytes32 _metadataDigest) external;
    // function trust(address _trustReceiver, uint96 _expiry) external; // Not needed for this contract
    // function isTrusted(address _truster, address _trustee) external view returns (bool); // Not needed for this contract
}

/* ========== MAIN CONTRACT ========== */

/**
 * @title CirclesPixelGrid
 * @notice A contract allowing users to purchase pixels on a 100x100 grid using Circles (CRC) tokens.
 * @dev Stores pixel ownership and metadata on-chain. Integrates with the Circles Hub.
 */
contract CirclesPixelGrid is IERC1155Receiver, IERC165 {
    // ---------- State Variables ----------

    /// @notice The address that deployed the contract and receives the CRC payments.
    address public owner;
    /// @notice The address of the Circles Hub contract.
    address public immutable hubAddress;
    /// @notice The price per pixel in CRC (wei).
    uint256 public constant PIXEL_PRICE = 100 * 1e18;
    /// @notice The maximum number of pixels a single user can purchase.
    uint256 public constant MAX_PIXELS_PER_USER = 10;
    /// @notice The dimension of the grid (e.g., 100 for a 100x100 grid).
    uint256 public constant GRID_SIZE = 100;
    /// @notice Total number of pixels available (GRID_SIZE * GRID_SIZE).
    uint256 public constant TOTAL_PIXELS = GRID_SIZE * GRID_SIZE;

    /// @notice Stores data for each pixel. Key is pixelId = y * GRID_SIZE + x.
    mapping(uint256 => PixelData) public pixels;
    /// @notice Tracks the number of pixels purchased by each user.
    mapping(address => uint256) public userPixelCount;
    /// @notice The total number of pixels sold so far.
    uint256 public pixelsSold;

    /// @notice Tracks if the organization has been registered with the Hub.
    bool public isRegistered;
    /// @notice The name used for organization registration.
    string public orgName;

    // ---------- Structs ----------

    /// @notice Represents the data associated with a single pixel.
    struct PixelData {
        address owner; // Address(0) if unowned
        uint24 color; // RGB color (e.g., 0xFF0000 for red)
        string linkUrl; // Optional URL associated with the pixel
    }

    // ---------- Events ----------

    /// @notice Emitted when a pixel is successfully purchased.
    event PixelPurchased(address indexed buyer, uint256 pixelId, uint256 x, uint256 y, uint24 color, string linkUrl);

    /// @notice Emitted when a CRC payment is refunded due to an invalid purchase attempt.
    event CRCRefunded(address indexed buyer, uint256 amount, string reason);

    /// @notice Emitted when a pixel's metadata (color, link) is updated by its owner.
    event PixelUpdated(address indexed owner, uint256 pixelId, uint256 x, uint256 y, uint24 color, string linkUrl);

    // ---------- Constructor ----------

    /**
     * @notice Sets up the contract, owner, Hub address, and registers the organization.
     * @param _orgName The name to register the organization with on the Circles Hub.
     * @param _hubAddress The address of the Circles Hub contract.
     */
    constructor(string memory _orgName, address _hubAddress) {
        owner = msg.sender;
        hubAddress = _hubAddress;
        orgName = _orgName;
        _registerOrg();
    }

    // ---------- Modifiers ----------

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // ---------- ERC1155 Receiver ----------

    /**
     * @notice Handles incoming CRC token transfers from the Circles Hub.
     * @dev This function is called by the Hub after a user initiates a `safeTransferFrom`.
     *      It validates the purchase, updates pixel ownership, and forwards CRC to the owner.
     * @param _operator The address which initiated the transfer (unused).
     * @param _from The address of the user sending CRC tokens (the buyer).
     * @param _id The ID of the token being transferred (CRC token ID).
     * @param _value The amount of CRC tokens received.
     * @param _data Encoded data containing purchase details: (uint256 x, uint256 y, uint24 color, string linkUrl).
     * @return `IERC1155Receiver.onERC1155Received.selector`.
     */
    function onERC1155Received(address _operator, address _from, uint256 _id, uint256 _value, bytes calldata _data)
        external
        override
        returns (bytes4)
    {
        // 1. Basic Checks
        require(msg.sender == hubAddress, "PixelGrid: Not from Hub");
        require(isRegistered, "PixelGrid: Org not registered");
        require(pixelsSold < TOTAL_PIXELS, "PixelGrid: Sold out");

        // 2. Decode Purchase Data
        (uint256 x, uint256 y, uint24 color, string memory linkUrl) =
            abi.decode(_data, (uint256, uint256, uint24, string));

        // 3. Validate Purchase Parameters
        require(x < GRID_SIZE && y < GRID_SIZE, "PixelGrid: Invalid coordinates");
        uint256 pixelId = y * GRID_SIZE + x;

        // Check length of linkUrl to prevent excessive gas costs (e.g., max 100 bytes)
        // require(bytes(linkUrl).length <= 100, "PixelGrid: Link URL too long"); // Add length check if desired

        // 4. Validate Purchase Conditions
        if (_value < PIXEL_PRICE) {
            _refund(_from, _id, _value, "Insufficient CRC");
            return this.onERC1155Received.selector;
        }
        if (userPixelCount[_from] >= MAX_PIXELS_PER_USER) {
            _refund(_from, _id, _value, "Max pixels reached");
            return this.onERC1155Received.selector;
        }
        if (pixels[pixelId].owner != address(0)) {
            _refund(_from, _id, _value, "Pixel already owned");
            return this.onERC1155Received.selector;
        }

        // 5. Update State
        userPixelCount[_from]++;
        pixelsSold++;
        pixels[pixelId] = PixelData(_from, color, linkUrl);

        // 6. Emit Event
        emit PixelPurchased(_from, pixelId, x, y, color, linkUrl);

        // 7. Forward Payment to Owner (transfer only the PIXEL_PRICE)
        // Note: Assumes the Hub contract allows transferring from this contract
        IERC1155(hubAddress).safeTransferFrom(address(this), owner, _id, PIXEL_PRICE, "");

        // 8. Handle potential refund for overpayment (optional, could let owner keep extra)
        if (_value > PIXEL_PRICE) {
            IERC1155(hubAddress).safeTransferFrom(
                address(this),
                _from, // Send excess back to buyer
                _id,
                _value - PIXEL_PRICE,
                ""
            );
            // Consider emitting an event for partial refund if needed
        }

        return this.onERC1155Received.selector;
    }

    /**
     * @notice Rejects batch transfers as pixel purchases are individual.
     */
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert("PixelGrid: Batch transfers not supported");
    }

    // ---------- Pixel Management Functions ----------

    /**
     * @notice Allows the owner of a pixel to update its color and link URL.
     * @param x The x-coordinate of the pixel.
     * @param y The y-coordinate of the pixel.
     * @param color The new color for the pixel (uint24 format).
     * @param linkUrl The new link URL for the pixel.
     */
    function updatePixelData(uint256 x, uint256 y, uint24 color, string calldata linkUrl) external {
        require(x < GRID_SIZE && y < GRID_SIZE, "PixelGrid: Invalid coordinates");
        uint256 pixelId = y * GRID_SIZE + x;

        // require(bytes(linkUrl).length <= 100, "PixelGrid: Link URL too long"); // Add length check if desired

        PixelData storage pixel = pixels[pixelId];
        require(pixel.owner == msg.sender, "PixelGrid: Not pixel owner");

        pixel.color = color;
        pixel.linkUrl = linkUrl;

        emit PixelUpdated(msg.sender, pixelId, x, y, color, linkUrl);
    }

    // ---------- View Functions ----------

    /**
     * @notice Gets the data for a specific pixel.
     * @param x The x-coordinate of the pixel.
     * @param y The y-coordinate of the pixel.
     * @return PixelData memory The data associated with the pixel.
     */
    function getPixelData(uint256 x, uint256 y) external view returns (PixelData memory) {
        require(x < GRID_SIZE && y < GRID_SIZE, "PixelGrid: Invalid coordinates");
        uint256 pixelId = y * GRID_SIZE + x;
        return pixels[pixelId];
    }

    /**
     * @notice Gets the number of pixels purchased by a specific user.
     * @param user The address of the user.
     * @return uint256 The number of pixels owned by the user.
     */
    function getUserPixelCount(address user) external view returns (uint256) {
        return userPixelCount[user];
    }

    // ---------- Internal Functions ----------

    /**
     * @dev Registers the contract as an organization with the Circles Hub.
     */
    function _registerOrg() internal {
        if (!isRegistered) {
            try IHub(hubAddress).registerOrganization(orgName, bytes32(0)) {
                isRegistered = true;
            } catch {
                // Handle potential registration failure (e.g., Hub address invalid, org name issues)
                console.log("PixelGrid: Failed to register organization with Hub at", hubAddress);
                // Depending on requirements, could revert or just log
            }
        }
    }

    /**
     * @dev Internal function to handle refunding CRC tokens via the Hub.
     */
    function _refund(address _to, uint256 _id, uint256 _value, string memory _reason) internal {
        IERC1155(hubAddress).safeTransferFrom(address(this), _to, _id, _value, "");
        emit CRCRefunded(_to, _value, _reason);
    }

    // ---------- ERC165 ----------

    /**
     * @notice Indicates support for ERC165 and IERC1155Receiver interfaces.
     */
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    // ---------- Owner Functions ----------

    /**
     * @notice Allows the owner to transfer ownership of the contract.
     * @param newOwner The address of the new owner.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "PixelGrid: New owner is zero address");
        owner = newOwner;
    }

    /**
     * @notice Allows the owner to update the organization name if registration failed initially or needs changing.
     * @param _newOrgName The new name for the organization.
     */
    function updateOrgName(string memory _newOrgName) external onlyOwner {
        orgName = _newOrgName;
        // Optionally, attempt re-registration if not already registered
        if (!isRegistered) {
            _registerOrg();
        }
    }

    /**
     * @notice Allows the owner to attempt organization registration again if it failed initially.
     */
    function retryRegisterOrg() external onlyOwner {
        require(!isRegistered, "PixelGrid: Already registered");
        _registerOrg();
    }
}
