// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Test } from "forge-std/src/Test.sol";
import { console2 } from "forge-std/src/console2.sol";
import { NFTMarketplace } from "../src/NFTMarketPlace.sol";
import { MockERC721 } from "./mocks/MockERC721.sol";

contract NFTMarketPlace is Test {
    NFTMarketplace marketplace;
    MockERC721 nft;
    
    address seller = makeAddr("seller");
    address buyer = makeAddr("buyer"); 
    uint256 tokenId = 1;
    uint256 price = 1 ether;
    
    function setUp() public {
        marketplace = new NFTMarketplace();
        nft = new MockERC721();
        vm.deal(buyer, 2 ether);
    }

    modifier givenUserWantsToListNFT() {
        vm.startPrank(seller);
        nft.mint(seller, tokenId);
        _;
    }

    function test_WhenNFTIsApprovedForMarketplace() external givenUserWantsToListNFT {
        nft.approve(address(marketplace), tokenId);
        marketplace.listNFT(address(nft), tokenId, price);
        
        assertTrue(nft.ownerOf(tokenId) == address(marketplace));
        (address payable listedSeller, uint256 listedPrice, bool isListed) = marketplace.nfts(address(nft), tokenId);
        assertTrue(listedSeller == seller);
        assertEq(listedPrice, price);
        assertTrue(isListed);
    }

    function test_WhenNFTIsNotApprovedForMarketplace() external givenUserWantsToListNFT {
        vm.expectRevert(abi.encodeWithSignature("ERC721InsufficientApproval(address,uint256)", address(marketplace), tokenId));
        marketplace.listNFT(address(nft), tokenId, price);
    }

    modifier givenNFTOwnerHasApprovedMarketplace() {
        nft.approve(address(marketplace), tokenId);
        _;
    }

    function test_WhenPriceIsGreaterThan0() external givenUserWantsToListNFT givenNFTOwnerHasApprovedMarketplace {
        marketplace.listNFT(address(nft), tokenId, price);
        (,uint256 listedPrice,) = marketplace.nfts(address(nft), tokenId);
        assertEq(listedPrice, price);
    }

    function test_WhenPriceIs0() external givenUserWantsToListNFT givenNFTOwnerHasApprovedMarketplace {
        marketplace.listNFT(address(nft), tokenId, 0);
        (,uint256 listedPrice,) = marketplace.nfts(address(nft), tokenId);
        assertEq(listedPrice, 0);
    }

    modifier givenUserWantsToBuyNFT() {
        vm.stopPrank();
        vm.startPrank(buyer);
        _;
    }

    modifier givenNFTIsListed() {
        vm.startPrank(seller);
        nft.mint(seller, tokenId);
        nft.approve(address(marketplace), tokenId);
        marketplace.listNFT(address(nft), tokenId, price);
        vm.stopPrank();
        _;
    }

    function test_WhenMsgValueEqualsPrice() external givenNFTIsListed givenUserWantsToBuyNFT {
        uint256 sellerInitialBalance = seller.balance;
        vm.deal(buyer, price); // Ensure buyer has funds
        marketplace.buyNFT{value: price}(address(nft), tokenId);
        
        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(seller.balance, sellerInitialBalance + price);
    }

    function test_WhenMsgValueExceedsPrice() external givenNFTIsListed givenUserWantsToBuyNFT {
        uint256 sellerInitialBalance = seller.balance;
        vm.deal(buyer, 2 * price); // Ensure buyer has excess funds
        marketplace.buyNFT{value: 2 * price}(address(nft), tokenId);
        
        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(seller.balance, sellerInitialBalance + price);
    }

    function test_WhenMsgValueIsLessThanPrice() external givenNFTIsListed givenUserWantsToBuyNFT {
        vm.expectRevert(NFTMarketplace.InsufficientFunds.selector);
        marketplace.buyNFT{value: 0.5 ether}(address(nft), tokenId);
    }

    function test_GivenNFTIsNotListed() external givenUserWantsToBuyNFT {
        vm.expectRevert(NFTMarketplace.NFTNotListed.selector);
        marketplace.buyNFT{value: price}(address(nft), tokenId);
    }

    modifier givenUserWantsToWithdrawNFT() {
        _;
    }

    modifier givenCallerIsSeller() {
        vm.startPrank(seller);
        _;
    }

    function test_WhenNFTIsListed() external givenNFTIsListed givenUserWantsToWithdrawNFT givenCallerIsSeller {
        marketplace.withdrawNFT(address(nft), tokenId);
        assertEq(nft.ownerOf(tokenId), seller);
    }

    function test_WhenNFTIsNotListed() external givenUserWantsToWithdrawNFT givenCallerIsSeller {
        vm.expectRevert();
        marketplace.withdrawNFT(address(nft), tokenId);
    }

    function test_GivenCallerIsNotSeller() external givenNFTIsListed givenUserWantsToWithdrawNFT {
        vm.startPrank(buyer);
        vm.expectRevert(NFTMarketplace.NotSeller.selector);
        marketplace.withdrawNFT(address(nft), tokenId);
    }

    modifier givenWhenOnERC721Received() {
        _;
    }

    function test_GivenEmptyData() external givenWhenOnERC721Received {
        bytes4 selector = marketplace.onERC721Received(address(0), address(0), 0, "");
        assertEq(selector, marketplace.onERC721Received.selector);
    }

    function test_GivenDataLengthIs32Bytes() external givenWhenOnERC721Received {
        vm.startPrank(address(nft));  // Set msg.sender to nft contract address
        bytes memory data = abi.encode(price);
        bytes4 selector = marketplace.onERC721Received(address(nft), seller, tokenId, data);
        assertEq(selector, marketplace.onERC721Received.selector);
        
        (address payable listedSeller, uint256 listedPrice, bool isListed) = marketplace.nfts(address(nft), tokenId);
        assertEq(address(listedSeller), seller);
        assertEq(listedPrice, price);
        assertTrue(isListed);
        vm.stopPrank();
    }

    function test_GivenDataLengthIsNot32Bytes() external givenWhenOnERC721Received {
        bytes memory invalidData = new bytes(31); // Any length other than 32
        vm.expectRevert(NFTMarketplace.InvalidDataLength.selector);
        marketplace.onERC721Received(address(0), address(0), 0, invalidData);
    }
}
