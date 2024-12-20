// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract NFTMarketplace is IERC721Receiver {
    /// Represents an NFT listed for sale on the marketplace.
    /// @param seller The address of the NFT owner who listed the NFT for sale.
    /// @param price The price the NFT is listed for.
    /// @param isListed Whether the NFT is currently listed for sale.
    struct NFT {
        address payable seller;
        uint256 price;
        bool isListed;
    }

    /// Mapping of NFT contracts to their listed NFTs, indexed by token ID.
    /// This mapping stores the details of all NFTs listed for sale on the marketplace.
    mapping(address nftContract => mapping(uint256 tokenId => NFT)) public nfts;

    /// Custom errors used in the NFTMarketplace contract.
    /// - `NotSeller`: Thrown when a non-owner of an NFT tries to perform an operation on it.
    /// - `NFTNotListed`: Thrown when an operation is attempted on an NFT that is not currently listed for sale.
    /// - `InsufficientFunds`: Thrown when the amount sent to buy an NFT is less than the listed price.
    /// - `InvalidDataLength`: Thrown when the data sent with the transfer is not the expected length.
    error NotSeller();
    error NFTNotListed();
    error InsufficientFunds();
    error InvalidDataLength();

    /// Events emitted by the NFTMarketplace contract:
    ///
    /// - `NFTListed`: Emitted when an NFT is listed for sale on the marketplace.
    ///   - `seller`: The address of the NFT owner who listed the NFT for sale.
    ///   - `nftAddress`: The address of the NFT contract.
    ///   - `tokenId`: The ID of the listed NFT.
    ///   - `price`: The price the NFT is listed for.
    ///
    /// - `NFTSold`: Emitted when an NFT is sold on the marketplace.
    ///   - `buyer`: The address of the buyer who purchased the NFT.
    ///   - `nftAddress`: The address of the NFT contract.
    ///   - `tokenId`: The ID of the sold NFT.
    ///   - `price`: The price the NFT was sold for.
    ///
    /// - `NFTWithdrawn`: Emitted when an NFT is withdrawn from the marketplace.
    ///   - `seller`: The address of the NFT owner who withdrew the NFT.
    ///   - `nftAddress`: The address of the NFT contract.
    ///   - `tokenId`: The ID of the withdrawn NFT.
    event NFTListed(address indexed seller, address indexed nftAddress, uint256 indexed tokenId, uint256 price);
    event NFTSold(address indexed buyer, address indexed nftAddress, uint256 indexed tokenId, uint256 price);
    event NFTWithdrawn(address indexed seller, address indexed nftAddress, uint256 indexed tokenId);

    /// Allows a seller to transfer an NFT to the marketplace and list it for sale in one step.
    /// @param nftAddress The address of the NFT contract.
    /// @param tokenId The ID of the NFT to be listed.
    /// @param price The price at which the NFT should be listed.
    function listNFT(address nftAddress, uint256 tokenId, uint256 price) external {
        // Transfer the NFT to the marketplace
        IERC721(nftAddress).safeTransferFrom(msg.sender, address(this), tokenId);
        
        // Initialize the NFT details in the mapping
        nfts[nftAddress][tokenId] = NFT(payable(msg.sender), price, true);
        
        // Emit the NFTListed event
        emit NFTListed(msg.sender, nftAddress, tokenId, price);
    }

    /// Allows a user to purchase an NFT listed on the marketplace.
    ///
    /// This function checks that the specified NFT is currently listed for sale on the marketplace.
    /// If the NFT is listed and the user has provided sufficient funds, the function transfers the
    /// NFT to the user, transfers the sale proceeds to the seller, and emits an `NFTSold` event.
    ///
    /// @param nftAddress The address of the NFT contract.
    /// @param tokenId The ID of the NFT to be purchased.
    function buyNFT(address nftAddress, uint256 tokenId) external payable {
        NFT memory nft = nfts[nftAddress][tokenId];
        if (!nft.isListed) revert NFTNotListed();
        if (msg.value < nft.price) revert InsufficientFunds();

        nfts[nftAddress][tokenId].isListed = false;
        delete nfts[nftAddress][tokenId];
        payable(nft.seller).transfer(nft.price);
        uint256 excess = msg.value - nft.price;
        if (excess > 0) {
            payable(msg.sender).transfer(excess);
        }
        IERC721(nftAddress).safeTransferFrom(address(this), msg.sender, tokenId);

        emit NFTSold(msg.sender, nftAddress, tokenId, nft.price);
    }

    /// Allows the owner of an NFT listed on the marketplace to withdraw the NFT.
    ///
    /// This function checks that the caller is the seller of the specified NFT, and that the NFT is
    /// not currently listed for sale. If these conditions are met, the function removes the NFT from
    /// the marketplace and transfers it back to the seller.
    ///
    /// @param nftAddress The address of the NFT contract.
    /// @param tokenId The ID of the NFT to be withdrawn.
    function withdrawNFT(address nftAddress, uint256 tokenId) external {
        NFT memory nft = nfts[nftAddress][tokenId];
        if (nft.seller != msg.sender) revert NotSeller();

        delete nfts[nftAddress][tokenId];
        IERC721(nftAddress).safeTransferFrom(address(this), msg.sender, tokenId);

        emit NFTWithdrawn(msg.sender, nftAddress, tokenId);
    }

    // This function is called when an NFT is transferred to this contract
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        // If data is empty, this is just a check for receiver capability
        if (data.length == 0) {
            return this.onERC721Received.selector;
        }

        // If data is provided, this is an actual listing
        if (data.length != 32) {
            revert InvalidDataLength();
        }
        uint256 price = abi.decode(data, (uint256));

        // Store the NFT details in the mapping
        nfts[msg.sender][tokenId] = NFT(payable(from), price, true);

        // Emit an event to notify that the NFT has been listed
        emit NFTListed(from, msg.sender, tokenId, price);

        return this.onERC721Received.selector;
    }
}
