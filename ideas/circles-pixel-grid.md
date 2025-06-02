# Brainstorming: Circles Pixel Grid Project

This document outlines the brainstorming and planning for the "Circles Pixel Grid" project, inspired by the Million Dollar Homepage concept but utilizing Circles (CRC) tokens.

## 1. Project Concept

*   **Core Idea:** A 100x100 pixel grid (10,000 pixels total) where users can purchase individual pixels.
*   **Payment:** Users pay using CRC tokens.
*   **Wallet:** Transactions initiated via the Metri wallet.
*   **Recipient:** Payments are sent to a dedicated smart contract acting as the organization's account.
*   **Cost:** Each pixel costs 100 CRC (100 * 10^18 wei).
*   **Limit:** Each user (wallet address) can purchase a maximum of 10 pixels.
*   **Organization:** The organization deploys the contract and receives the CRC payments.
*   **State:** Pixel ownership and associated metadata (color, optional link) are stored entirely on-chain for maximum decentralization and transparency.

## 2. Technical Architecture

```mermaid
graph LR
    subgraph Frontend
        UI[Web UI (HTML/CSS/JS)]
        Lib[ethers.js / viem]
        Wallet[Metri Wallet]
    end

    subgraph Blockchain (Gnosis Chain / Testnet)
        Contract[CirclesPixelGrid.sol]
        Hub[Circles Hub]
    end

    User[User] --> UI
    UI --> Lib
    Lib --> Wallet
    Wallet --> Contract
    Lib --> Contract(Read Data)
    Contract --> Hub(Register Org, Trust)
    Wallet -- CRC Transfer --> Hub -- Forward CRC --> Contract
```

*   **Frontend:** A simple, static web application (HTML, CSS, JavaScript). A lightweight framework like Svelte or even vanilla JS could be used to minimize complexity.
*   **Blockchain Interaction:** Use `ethers.js` or `viem` library in the frontend to interact with the smart contract (reading grid state, initiating purchases).
*   **Smart Contract:** A Solidity contract (`CirclesPixelGrid.sol`) deployed on a suitable network (e.g., Gnosis Chain for mainnet, Chiado for testnet).
*   **Wallet Integration:** Specific integration with the Metri wallet is required to handle the CRC (ERC1155) transfer process.

## 3. Smart Contract Design (`CirclesPixelGrid.sol`)

*   **Base:** Adapt existing `CRCNFTTicketSeller.sol` or `NFTSellerNoArgs.sol` for Hub integration and CRC receiving logic (ERC1155Receiver).
*   **State Variables:**
    *   `address public owner`: Deployer/Organization address receiving funds.
    *   `address public immutable hubAddress`: Circles Hub address (set in constructor).
    *   `uint256 public constant PIXEL_PRICE = 100 * 1e18`: Price per pixel.
    *   `uint256 public constant MAX_PIXELS_PER_USER = 10`: Max pixels per address.
    *   `uint256 public constant GRID_SIZE = 100`: Dimension of the grid.
    *   `mapping(uint256 => PixelData) public pixels`: Stores data for each pixel. Key is `pixelId = y * GRID_SIZE + x`.
    *   `mapping(address => uint256) public userPixelCount`: Tracks pixels bought per user.
    *   `uint256 public pixelsSold`: Total number of pixels sold.
    *   `bool public isRegistered`: Tracks organization registration status.
    *   `string public orgName`: Organization name for registration.
*   **Structs:**
    *   `struct PixelData { address owner; uint24 color; string linkUrl; }` (Using `uint24` for color is more gas-efficient than string). Consider `bytes` for `linkUrl` with length limits for gas savings.
*   **Events:**
    *   `event PixelPurchased(address indexed buyer, uint256 pixelId, uint256 x, uint256 y, uint24 color, string linkUrl)`
    *   `event CRCRefunded(address indexed buyer, uint256 amount, string reason)`
    *   `event PixelUpdated(address indexed owner, uint256 pixelId, uint256 x, uint256 y, uint24 color, string linkUrl)`
*   **Functions:**
    *   `constructor(string memory _orgName)`: Sets owner, hub address, org name. Calls `_registerOrg()`.
    *   `onERC1155Received(address _operator, address _from, uint256 _id, uint256 _value, bytes calldata _data)`:
        *   `require(msg.sender == hubAddress, "Not from Hub")`.
        *   Decode `_data` to get `x`, `y`, `color`, `linkUrl`. Use `abi.decode`.
        *   `require(_value >= PIXEL_PRICE, "Insufficient CRC")`.
        *   `require(userPixelCount[_from] < MAX_PIXELS_PER_USER, "Max pixels reached")`.
        *   Calculate `pixelId = y * GRID_SIZE + x`.
        *   `require(pixels[pixelId].owner == address(0), "Pixel already owned")`.
        *   Update state: `userPixelCount[_from]++`, `pixelsSold++`, `pixels[pixelId] = PixelData(_from, color, linkUrl)`.
        *   Emit `PixelPurchased`.
        *   Forward CRC to `owner` via `IERC1155(hubAddress).safeTransferFrom(address(this), owner, _id, PIXEL_PRICE, "")`.
        *   Handle potential refunds for excess value or errors.
        *   Return `this.onERC1155Received.selector`.
    *   `updatePixelData(uint256 x, uint256 y, uint24 color, string calldata linkUrl)`:
        *   Calculate `pixelId`.
        *   `require(pixels[pixelId].owner == msg.sender, "Not pixel owner")`.
        *   Update `pixels[pixelId].color` and `pixels[pixelId].linkUrl`.
        *   Emit `PixelUpdated`.
    *   `getPixelData(uint256 x, uint256 y) view returns (PixelData memory)`: Returns data for a specific pixel.
    *   `getAllPixels() view returns (PixelData[] memory)`: Returns data for all pixels (potentially very large/gassy, consider alternatives or pagination if needed). Maybe return only owners or IDs of owned pixels.
    *   `getUserPixelCount(address user) view returns (uint256)`: Returns pixel count for a user.
    *   `_registerOrg()`: Internal function called by constructor to register with the Hub.
    *   `supportsInterface(bytes4 interfaceId) pure returns (bool)`: Support `IERC1155Receiver.interfaceId` and `IERC165.interfaceId`.

## 4. On-Chain State Strategy

*   **Preference:** Store all essential data on-chain for decentralization and transparency.
*   **Pixel Data:** `owner` (address), `color` (uint24), `linkUrl` (string or bytes).
*   **Gas Considerations:**
    *   Storing strings (`linkUrl`) is gas-intensive. Impose a character limit (e.g., 100 chars) or use `bytes` which is generally cheaper.
    *   Storing `color` as `uint24` (e.g., 0xFF0000 for red) is much cheaper than a hex string.
    *   Reading the entire grid state (`getAllPixels`) could be very expensive. The UI might need to fetch data pixel by pixel or in batches, or rely on events.

## 5. UI/UX Considerations

*   **Grid Display:** Render a 100x100 grid using HTML/CSS.
*   **Pixel State:** Fetch pixel data (owner, color) from the contract to color the grid squares. Owned pixels show their color; unowned pixels are distinct (e.g., grey).
*   **Interaction:**
    *   Hover/click on a pixel shows owner address and link (if set).
    *   Clicking an *available* pixel initiates the purchase flow.
*   **Purchase Flow:**
    1.  User clicks an available pixel (gets `x`, `y`).
    2.  UI prompts for color (color picker -> `uint24`) and optional link URL.
    3.  UI connects to Metri Wallet.
    4.  UI constructs the `bytes _data` payload using `abi.encode(x, y, color, linkUrl)`.
    5.  UI initiates `safeTransferFrom` call via Metri to the **Hub address**, specifying the **Pixel Grid contract address** as the recipient, the CRC token ID, `PIXEL_PRICE` as the amount, and the encoded `_data`. *Crucially, the transfer must go via the Hub for the `onERC1155Received` hook to trigger correctly.*
    6.  UI displays transaction status (pending, success, failure).
    7.  Grid updates upon successful purchase (ideally via event listening, fallback to polling).
*   **User Info:** Display connected user's address and their current pixel count (`userPixelCount`).

## 6. Implementation Roadmap (Simplified)

1.  **Phase 1: Smart Contract Core:**
    *   Develop `CirclesPixelGrid.sol` with state variables, structs, constructor, `onERC1155Received` (core purchase logic), `getPixelData`, `supportsInterface`.
    *   Basic Forge tests for purchase and state changes.
    *   Deploy to Chiado testnet.
2.  **Phase 2: Basic UI & Read:**
    *   HTML/CSS grid.
    *   ethers.js/viem setup.
    *   Connect to Metri.
    *   Fetch and display grid state from the testnet contract.
3.  **Phase 3: Purchase & Update Flow:**
    *   Implement pixel selection UI.
    *   Input for color/link.
    *   Implement `safeTransferFrom` call via Metri with encoded data.
    *   Implement `updatePixelData` function call.
    *   Handle transaction feedback.
4.  **Phase 4: Refinement & Mainnet:**
    *   Refine UI/UX (loading states, error handling).
    *   Add event listeners for real-time updates.
    *   Comprehensive testing (Forge).
    *   Gas optimization review.
    *   Deploy to Gnosis Chain.

## 7. Potential Challenges & Solutions

*   **Gas Costs (Strings/Storage):**
    *   *Solution:* Use `uint24` for color. Use `bytes` for `linkUrl` and enforce length limits. Optimize storage layout.
*   **Data Encoding/Decoding:**
    *   *Solution:* Use `abi.encode` on the frontend and `abi.decode` in the contract. Document the exact schema. Ensure frontend sends data in the correct order/types.
*   **UI Performance (Reading Grid):**
    *   *Solution:* Use contract events (`PixelPurchased`, `PixelUpdated`) to update the UI state incrementally. Fetch initial state efficiently (maybe paginated or using multicall). Avoid fetching all 10,000 pixels at once if possible.
*   **Metri Wallet CRC Transfer:**
    *   *Solution:* Ensure the `safeTransferFrom` call targets the Hub, includes the correct CRC token ID for the user, specifies the Pixel Grid contract as the recipient, and includes the correctly encoded `bytes _data`. Test this flow thoroughly.
*   **Transaction Reverts:**
    *   *Solution:* Provide clear UI feedback on why a transaction failed (e.g., "Pixel already owned", "Insufficient CRC", "Max pixels reached"). Use descriptive `require` messages in the contract.

This brainstorming document provides a solid foundation for the project.
