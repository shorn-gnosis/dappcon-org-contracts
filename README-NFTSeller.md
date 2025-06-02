# NFT Seller for Circles

This project provides a set of contracts and scripts for creating NFT sellers that accept Circles (CRC) tokens as payment. The NFT seller is an organization in the Circles ecosystem that can receive CRC tokens and send NFTs in return.

## Contracts

### NFTSellerNoArgs

The main contract that:
- Registers as an organization in the Circles ecosystem
- Accepts any CRC tokens from the hub (no token ID restrictions)
- Sends NFTs as rewards
- Forwards the CRC tokens to the owner

### NFTSellerFactory

A factory contract that:
- Creates and configures NFTSellerNoArgs contracts
- Provides a one-click default seller with predefined parameters
- Allows creating custom sellers with specific parameters

## Deployment Scripts

### DeployNFTSellerFactory

Deploys the NFTSellerFactory contract:

```bash
# Set your private key
export PRIVATE_KEY=your_private_key

# Deploy the factory
forge script script/DeployNFTSellerFactory.s.sol --rpc-url https://rpc.gnosischain.com --chain 100 --private-key $PRIVATE_KEY --broadcast
```

### CreateNFTSeller

Creates a new NFT seller using the factory:

```bash
# Set required parameters
export PRIVATE_KEY=your_private_key
export FACTORY_ADDRESS=deployed_factory_address
export ORG_NAME="NFT Ticket Seller"
export TRUSTED_ADDRESS=0xc175a0c71f1eDA836ebbF3Ab0e32Fc8865FdEe91
export NFT_CONTRACT=0xa53A5773b9d4cE2cf5b42A7711239833b31ffc38
export OFFER_PRICE=5000000000000000000  # 5 CRC

# Optional parameters
export OFFER_START=1743619200  # Unix timestamp
export OFFER_END=1775155200    # Unix timestamp
export REQUIRE_TRUSTED_BY=0x0000000000000000000000000000000000000000
export ONCE_PER_USER=0         # 0 for false, 1 for true
export ONCE_PER_DAY=0          # 0 for false, 1 for true

# Create the seller
forge script script/CreateNFTSeller.s.sol --rpc-url https://rpc.gnosischain.com --chain 100 --private-key $PRIVATE_KEY --broadcast
```

### AddNFTTokenIds

Adds NFT token IDs to an existing seller:

```bash
# Set parameters
export PRIVATE_KEY=your_private_key
export SELLER_ADDRESS=deployed_seller_address
export TOKEN_IDS=1,2,3,4,5  # Comma-separated list of token IDs

# Add token IDs
forge script script/AddNFTTokenIds.s.sol --rpc-url https://rpc.gnosischain.com --chain 100 --private-key $PRIVATE_KEY --broadcast
```

### TrustAddressInSeller

Trusts an additional address in an existing seller:

```bash
# Set parameters
export PRIVATE_KEY=your_private_key
export SELLER_ADDRESS=deployed_seller_address
export TRUSTED_ADDRESS=0x42cEDde51198D1773590311E2A340DC06B24cB37
export EXPIRY=4102444800  # Optional: Unix timestamp for expiry (default: 100 years from now)

# Trust the address
forge script script/TrustAddressInSeller.s.sol --rpc-url https://rpc.gnosischain.com --chain 100 --private-key $PRIVATE_KEY --broadcast
```

## Usage Flow

1. **Deploy the factory**:
   - Use the DeployNFTSellerFactory script
   - Note the factory address

2. **Create an NFT seller**:
   - Use the CreateNFTSeller script with the factory address
   - Configure parameters like organization name, trusted address, and NFT contract
   - Note the seller address

3. **Add NFT token IDs**:
   - Transfer NFTs to the seller contract
   - Use the AddNFTTokenIds script to add the token IDs to the available list

4. **Receive CRC and send NFTs**:
   - The seller will automatically:
     - Accept CRC tokens from trusted addresses
     - Send an NFT in return
     - Forward the CRC tokens to the owner

## Trust Relationships

- The seller trusts the address specified in `TRUSTED_ADDRESS`
- To trust additional addresses, call `setTrustedAddress` on the seller contract
- The seller accepts CRC tokens from any address that is trusted

## Customization

You can customize various aspects of the NFT seller:
- Organization name
- Trusted address
- NFT contract
- Offer price
- Offer start and end times
- Usage limits (once per user, once per day)
- Required trust relationships

## Troubleshooting

If you encounter issues:
1. Make sure the NFT contract is correctly configured
2. Ensure the seller has NFTs available
3. Check that the trusted address is correctly set
4. Verify that the CRC amount is sufficient
