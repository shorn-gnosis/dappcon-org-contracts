// --- Constants and Variables ---
const GRID_SIZE = 100; // Must match contract GRID_SIZE
const PIXEL_PRICE_CRC = 100; // Must match contract PIXEL_PRICE / 1e18
const HUB_ADDRESS = "0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8"; // Gnosis/Chiado Hub Address (User confirmed)

// TODO: Replace with deployed contract address and ABI
const CONTRACT_ADDRESS = "0x..."; // Replace with deployed address
const CONTRACT_ABI = [
    // Add ABI from compiled CirclesPixelGrid.sol here
    // Example structure:
    "event PixelPurchased(address indexed buyer, uint256 pixelId, uint256 x, uint256 y, uint24 color, string linkUrl)",
    "event PixelUpdated(address indexed owner, uint256 pixelId, uint256 x, uint256 y, uint24 color, string linkUrl)",
    "function pixels(uint256 pixelId) view returns (address owner, uint24 color, string linkUrl)",
    "function getPixelData(uint256 x, uint256 y) view returns (tuple(address owner, uint24 color, string linkUrl))",
    "function getUserPixelCount(address user) view returns (uint256)",
    "function updatePixelData(uint256 x, uint256 y, uint24 color, string linkUrl)",
    // onERC1155Received is called by the Hub, not directly by frontend
];

// TODO: Replace with actual CRC Token ID for the user on the target network
// This needs to be determined based on the user's Metri wallet address
let userCRCTokenId = null; // Will be set after wallet connection

let provider;
let signer;
let contract;
let userAddress;

// DOM Elements
const gridContainer = document.getElementById('gridContainer');
const connectButton = document.getElementById('connectButton');
const userInfo = document.getElementById('userInfo');
const pixelInfoDiv = document.getElementById('pixelInfo');
const pixelDetailsDiv = document.getElementById('pixelDetails');
const pixelCoordsSpan = document.getElementById('pixelCoords');
const pixelOwnerSpan = document.getElementById('pixelOwner');
const pixelColorPreviewSpan = document.getElementById('pixelColorPreview');
const pixelColorValueSpan = document.getElementById('pixelColorValue');
const pixelLinkAnchor = document.getElementById('pixelLink');
const purchaseSectionDiv = document.getElementById('purchaseSection');
const colorPicker = document.getElementById('colorPicker');
const linkInput = document.getElementById('linkInput');
const purchaseButton = document.getElementById('purchaseButton');
const purchaseStatusP = document.getElementById('purchaseStatus');
const updateSectionDiv = document.getElementById('updateSection');
const updateColorPicker = document.getElementById('updateColorPicker');
const updateLinkInput = document.getElementById('updateLinkInput');
const updateButton = document.getElementById('updateButton');
const updateStatusP = document.getElementById('updateStatus');

let selectedPixel = { x: null, y: null };

// --- Initialization ---

window.addEventListener('load', async () => {
    console.log("Initializing App...");
    initializeGrid();
    setupEventListeners();

    // Check if Metri Wallet (or any EIP-1193 provider) is available
    if (window.ethereum) {
        provider = new ethers.providers.Web3Provider(window.ethereum);
        // Optional: Try to connect automatically if already approved
        // connectWallet();
        console.log("Ethereum provider detected.");
    } else {
        console.log("Metri Wallet (or other Ethereum provider) not detected.");
        userInfo.textContent = "Please install Metri Wallet!";
    }

    // TODO: Instantiate contract once address and ABI are available
    // if (CONTRACT_ADDRESS !== "0x..." && provider) {
    //     contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, provider);
    //     await loadGridData();
    // } else {
    //     console.warn("Contract address or ABI not set, or provider not available.");
    // }
});

// --- Grid Functions ---

function initializeGrid() {
    gridContainer.innerHTML = ''; // Clear existing grid
    gridContainer.style.gridTemplateColumns = `repeat(${GRID_SIZE}, 1fr)`;
    gridContainer.style.gridTemplateRows = `repeat(${GRID_SIZE}, 1fr)`;

    for (let y = 0; y < GRID_SIZE; y++) {
        for (let x = 0; x < GRID_SIZE; x++) {
            const pixel = document.createElement('div');
            pixel.classList.add('pixel');
            pixel.dataset.x = x;
            pixel.dataset.y = y;
            pixel.id = `pixel-${x}-${y}`;
            // Initial background set by container
            gridContainer.appendChild(pixel);
        }
    }
    console.log(`Initialized ${GRID_SIZE}x${GRID_SIZE} grid structure.`);
}

async function loadGridData() {
    if (!contract) {
        console.error("Contract not initialized.");
        return;
    }
    console.log("Loading grid data from contract...");
    // TODO: Implement efficient loading
    // Naive approach: Fetch each pixel individually (SLOW for 10k pixels!)
    // Better: Use multicall, or fetch only owned pixels if contract supports it, or rely on events.
    // For now, just log a message.
    console.warn("loadGridData needs implementation (fetching 10k pixels is slow).");

    // Example of fetching one pixel:
    // try {
    //     const pixelData = await contract.getPixelData(0, 0);
    //     updatePixelElement(0, 0, pixelData);
    // } catch (error) {
    //     console.error("Error fetching pixel (0,0):", error);
    // }
}

function updatePixelElement(x, y, pixelData) {
    const pixelElement = document.getElementById(`pixel-${x}-${y}`);
    if (!pixelElement) return;

    if (pixelData.owner !== ethers.constants.AddressZero) {
        const colorHex = ethers.utils.hexZeroPad(ethers.utils.hexlify(pixelData.color), 3).substring(2); // uint24 to hex #RRGGBB
        pixelElement.style.backgroundColor = `#${colorHex}`;
        pixelElement.dataset.owner = pixelData.owner;
        pixelElement.dataset.color = `#${colorHex}`;
        pixelElement.dataset.link = pixelData.linkUrl;
    } else {
        pixelElement.style.backgroundColor = ''; // Use container default
        delete pixelElement.dataset.owner;
        delete pixelElement.dataset.color;
        delete pixelElement.dataset.link;
    }
}

// --- Wallet Interaction ---

async function connectWallet() {
    if (!window.ethereum) {
        userInfo.textContent = "Metri Wallet not found!";
        return;
    }
    try {
        console.log("Requesting accounts...");
        await provider.send("eth_requestAccounts", []);
        signer = provider.getSigner();
        userAddress = await signer.getAddress();
        console.log("Connected address:", userAddress);

        // TODO: Determine user's CRC Token ID
        // This is complex as it depends on the user's Circles profile/trusts.
        // For now, we might need to ask the user or use a fixed one for testing.
        // userCRCTokenId = ethers.BigNumber.from(userAddress); // This is the common pattern
        console.warn("User CRC Token ID determination needed.");
        userCRCTokenId = ethers.BigNumber.from(userAddress); // ASSUMPTION for now

        userInfo.textContent = `Connected: ${userAddress.substring(0, 6)}...${userAddress.substring(userAddress.length - 4)} | CRC ID: ${userCRCTokenId ? userCRCTokenId.toString() : 'N/A'}`;
        connectButton.textContent = "Connected";
        connectButton.disabled = true;

        // Re-initialize contract with signer for transactions
        if (CONTRACT_ADDRESS !== "0x...") {
             contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, signer);
             console.log("Contract connected with signer.");
             // Optionally refresh user-specific info (e.g., pixel count)
             updateUserInfoDisplay();
        }

    } catch (error) {
        console.error("Error connecting wallet:", error);
        userInfo.textContent = `Connection failed: ${error.message}`;
    }
}

async function updateUserInfoDisplay() {
     if (!userAddress || !contract) return;
     try {
        const count = await contract.getUserPixelCount(userAddress);
        userInfo.textContent = `Connected: ${userAddress.substring(0, 6)}...${userAddress.substring(userAddress.length - 4)} | Pixels: ${count.toString()}/${CirclesPixelGrid.MAX_PIXELS_PER_USER} | CRC ID: ${userCRCTokenId ? userCRCTokenId.toString() : 'N/A'}`;
     } catch (error) {
        console.error("Error fetching user pixel count:", error);
     }
}


// --- Pixel Interaction ---

function handlePixelClick(event) {
    if (!event.target.classList.contains('pixel')) return;

    const x = parseInt(event.target.dataset.x);
    const y = parseInt(event.target.dataset.y);
    selectedPixel = { x, y };

    console.log(`Pixel clicked: (${x}, ${y})`);
    pixelCoordsSpan.textContent = `(${x}, ${y})`;

    const owner = event.target.dataset.owner;
    const color = event.target.dataset.color || '#e0e0e0'; // Default grey
    const link = event.target.dataset.link;

    if (owner) { // Pixel is owned
        pixelOwnerSpan.textContent = owner;
        pixelColorPreviewSpan.style.backgroundColor = color;
        pixelColorValueSpan.textContent = color;
        if (link) {
            pixelLinkAnchor.href = link;
            pixelLinkAnchor.textContent = link;
            pixelLinkAnchor.style.display = 'inline';
        } else {
            pixelLinkAnchor.textContent = 'N/A';
            pixelLinkAnchor.style.display = 'none';
        }
        purchaseSectionDiv.style.display = 'none'; // Hide purchase section

        // Show update section ONLY if connected user is the owner
        if (userAddress && owner.toLowerCase() === userAddress.toLowerCase()) {
            updateColorPicker.value = color;
            updateLinkInput.value = link || '';
            updateSectionDiv.style.display = 'block';
            updateStatusP.textContent = '';
        } else {
            updateSectionDiv.style.display = 'none';
        }

    } else { // Pixel is available
        pixelOwnerSpan.textContent = 'Available';
        pixelColorPreviewSpan.style.backgroundColor = '#e0e0e0';
        pixelColorValueSpan.textContent = 'N/A';
        pixelLinkAnchor.textContent = 'N/A';
        pixelLinkAnchor.style.display = 'none';
        updateSectionDiv.style.display = 'none'; // Hide update section

        // Show purchase section ONLY if wallet is connected
        if (userAddress) {
            purchaseSectionDiv.style.display = 'block';
            purchaseStatusP.textContent = '';
            // Reset defaults
            colorPicker.value = '#ffffff';
            linkInput.value = '';
        } else {
             purchaseSectionDiv.style.display = 'none';
             purchaseStatusP.textContent = 'Connect wallet to purchase.';
        }
    }

    pixelDetailsDiv.style.display = 'block';
}

async function purchasePixel() {
    if (!contract || !signer || !userAddress || selectedPixel.x === null || !userCRCTokenId) {
        purchaseStatusP.textContent = "Error: Wallet not connected or contract/CRC ID not ready.";
        console.error("Purchase prerequisites not met:", { contract, signer, userAddress, selectedPixel, userCRCTokenId });
        return;
    }

    const { x, y } = selectedPixel;
    const colorHex = colorPicker.value; // e.g., #RRGGBB
    const linkUrl = linkInput.value || "";

    // Convert hex color to uint24
    const colorUint24 = parseInt(colorHex.substring(1), 16);

    // Encode data for onERC1155Received
    const purchaseData = ethers.utils.defaultAbiCoder.encode(
        ['uint256', 'uint256', 'uint24', 'string'],
        [x, y, colorUint24, linkUrl]
    );

    purchaseStatusP.textContent = "Preparing transaction...";
    console.log(`Attempting purchase: Pixel(${x},${y}), Color(${colorHex}/${colorUint24}), Link(${linkUrl}), UserCRC(${userCRCTokenId.toString()})`);
    console.log("Encoded data:", purchaseData);

    try {
        // Get the Hub contract instance to call safeTransferFrom
        // We need the Hub's ABI for this specific function
        const hubAbi = ["function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes data)"];
        const hubContract = new ethers.Contract(HUB_ADDRESS, hubAbi, signer);

        purchaseStatusP.textContent = "Please approve transaction in Metri Wallet...";

        // User (signer) calls safeTransferFrom on the Hub
        // Sending CRC from user to the PixelGrid contract
        const tx = await hubContract.safeTransferFrom(
            userAddress,        // from: the user's address
            CONTRACT_ADDRESS,   // to: the PixelGrid contract address
            userCRCTokenId,     // id: user's CRC token ID
            ethers.utils.parseEther(PIXEL_PRICE_CRC.toString()), // amount: pixel price
            purchaseData        // data: encoded pixel info
        );

        purchaseStatusP.textContent = `Transaction sent: ${tx.hash}. Waiting for confirmation...`;
        console.log("Transaction sent:", tx.hash);

        const receipt = await tx.wait();
        console.log("Transaction confirmed:", receipt);

        purchaseStatusP.textContent = `Pixel (${x}, ${y}) purchased successfully! Tx: ${receipt.transactionHash}`;
        // Refresh grid and user info
        // TODO: Ideally listen for event, but for now manual refresh
        const pixelData = await contract.getPixelData(x, y);
        updatePixelElement(x, y, pixelData);
        updateUserInfoDisplay();
        // Hide purchase section after success
        purchaseSectionDiv.style.display = 'none';


    } catch (error) {
        console.error("Purchase failed:", error);
        purchaseStatusP.textContent = `Purchase failed: ${error?.data?.message || error?.message || 'Unknown error'}`;
    }
}

async function updatePixel() {
     if (!contract || !signer || !userAddress || selectedPixel.x === null) {
        updateStatusP.textContent = "Error: Wallet not connected or contract not ready.";
        return;
    }

    const { x, y } = selectedPixel;
    const colorHex = updateColorPicker.value;
    const linkUrl = updateLinkInput.value || "";
    const colorUint24 = parseInt(colorHex.substring(1), 16);

    updateStatusP.textContent = "Preparing update transaction...";
    console.log(`Attempting update: Pixel(${x},${y}), Color(${colorHex}/${colorUint24}), Link(${linkUrl})`);

    try {
        updateStatusP.textContent = "Please approve update transaction in Metri Wallet...";
        const tx = await contract.updatePixelData(x, y, colorUint24, linkUrl);

        updateStatusP.textContent = `Update transaction sent: ${tx.hash}. Waiting for confirmation...`;
        console.log("Update transaction sent:", tx.hash);

        const receipt = await tx.wait();
        console.log("Update transaction confirmed:", receipt);

        updateStatusP.textContent = `Pixel (${x}, ${y}) updated successfully! Tx: ${receipt.transactionHash}`;
        // Refresh grid
        const pixelData = await contract.getPixelData(x, y);
        updatePixelElement(x, y, pixelData);
        // Update details view
        handlePixelClick({ target: document.getElementById(`pixel-${x}-${y}`) });


    } catch (error) {
         console.error("Update failed:", error);
        updateStatusP.textContent = `Update failed: ${error?.data?.message || error?.message || 'Unknown error'}`;
    }
}


// --- Event Listeners ---

function setupEventListeners() {
    connectButton.addEventListener('click', connectWallet);
    gridContainer.addEventListener('click', handlePixelClick);
    purchaseButton.addEventListener('click', purchasePixel);
    updateButton.addEventListener('click', updatePixel);

    // TODO: Add contract event listeners for real-time updates
    // if (contract) {
    //     console.log("Setting up event listeners...");
    //     contract.on("PixelPurchased", (buyer, pixelId, x, y, color, linkUrl, event) => {
    //         console.log("Event: PixelPurchased", { buyer, pixelId, x, y, color, linkUrl });
    //         // Update UI directly
    //         const pixelData = { owner: buyer, color: color, linkUrl: linkUrl };
    //         updatePixelElement(x.toNumber(), y.toNumber(), pixelData);
    //         // If the buyer is the current user, update their info
    //         if (userAddress && buyer.toLowerCase() === userAddress.toLowerCase()) {
    //             updateUserInfoDisplay();
    //         }
    //     });
    //      contract.on("PixelUpdated", (owner, pixelId, x, y, color, linkUrl, event) => {
    //          console.log("Event: PixelUpdated", { owner, pixelId, x, y, color, linkUrl });
    //          const pixelData = { owner: owner, color: color, linkUrl: linkUrl };
    //          updatePixelElement(x.toNumber(), y.toNumber(), pixelData);
    //      });
    // }
}
