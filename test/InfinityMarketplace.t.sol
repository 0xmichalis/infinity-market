// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {InfinityMarketplace} from "../src/InfinityMarketplace.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {MockERC1155} from "./mocks/MockERC1155.sol";

contract InfinityMarketplaceTest is Test {
    InfinityMarketplace public marketplace;
    MockERC721 public erc721;
    MockERC1155 public erc1155;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant INITIAL_BALANCE = 100 ether;
    uint256 public constant TOKEN_ID = 1;
    uint256 public constant TOKEN_AMOUNT = 5;
    uint256 public constant PRICE = 1 ether;

    event Deposited(
        address indexed nftContract,
        uint256 indexed tokenId,
        address indexed depositor,
        uint256 amount,
        InfinityMarketplace.NFTType nftType
    );

    event OfferCreated(bytes32 offerHash);
    event OfferCancelled(bytes32 offerHash);
    event OfferSettled(bytes32 offerHash);

    function setUp() public {
        marketplace = new InfinityMarketplace();
        erc721 = new MockERC721();
        erc1155 = new MockERC1155();

        // Fund test accounts
        vm.deal(alice, INITIAL_BALANCE);
        vm.deal(bob, INITIAL_BALANCE);
    }

    function test_DepositERC721() public {
        // Mint token to alice
        erc721.mint(alice, TOKEN_ID);

        // Deposit as alice
        vm.startPrank(alice);

        vm.expectEmit(true, true, true, true);
        emit Deposited(address(erc721), TOKEN_ID, alice, 1, InfinityMarketplace.NFTType.ERC721);

        erc721.safeTransferFrom(alice, address(marketplace), TOKEN_ID);
        vm.stopPrank();

        // Verify deposit
        (uint256 balance, InfinityMarketplace.NFTType nftType) =
            marketplace.deposits(alice, address(erc721), TOKEN_ID);
        assertEq(balance, 1);
        assertEq(uint256(nftType), uint256(InfinityMarketplace.NFTType.ERC721));
    }

    function test_DepositERC1155() public {
        // Mint tokens to alice
        erc1155.mint(alice, TOKEN_ID, TOKEN_AMOUNT);

        // Deposit as alice
        vm.startPrank(alice);

        vm.expectEmit(true, true, true, true);
        emit Deposited(
            address(erc1155), TOKEN_ID, alice, TOKEN_AMOUNT, InfinityMarketplace.NFTType.ERC1155
        );

        erc1155.safeTransferFrom(alice, address(marketplace), TOKEN_ID, TOKEN_AMOUNT, "");
        vm.stopPrank();

        // Verify deposit
        (uint256 balance, InfinityMarketplace.NFTType nftType) =
            marketplace.deposits(alice, address(erc1155), TOKEN_ID);
        assertEq(balance, TOKEN_AMOUNT);
        assertEq(uint256(nftType), uint256(InfinityMarketplace.NFTType.ERC1155));
    }

    function test_CreateBuyOffer() public {
        vm.startPrank(bob);

        vm.expectEmit(true, true, true, true);
        bytes32 expectedOfferHash = marketplace.getOfferHash(
            InfinityMarketplace.Offer({
                maker: bob,
                nftContract: address(erc721),
                tokenId: TOKEN_ID,
                amount: 1,
                price: PRICE,
                offerType: InfinityMarketplace.OfferType.Buy
            })
        );
        emit OfferCreated(expectedOfferHash);

        marketplace.createOffer{value: PRICE}(
            address(erc721), TOKEN_ID, PRICE, 1, InfinityMarketplace.OfferType.Buy
        );
        vm.stopPrank();

        // Verify offer
        (
            address maker,
            address nftContract,
            uint256 tokenId,
            uint256 amount,
            uint256 price,
            InfinityMarketplace.OfferType offerType
        ) = marketplace.offers(expectedOfferHash);

        assertEq(maker, bob);
        assertEq(nftContract, address(erc721));
        assertEq(tokenId, TOKEN_ID);
        assertEq(amount, 1);
        assertEq(price, PRICE);
        assertEq(uint256(offerType), uint256(InfinityMarketplace.OfferType.Buy));
    }

    function test_CreateSellOffer() public {
        // First deposit NFT
        erc721.mint(alice, TOKEN_ID);
        vm.startPrank(alice);
        erc721.safeTransferFrom(alice, address(marketplace), TOKEN_ID);

        vm.expectEmit(true, true, true, true);
        bytes32 expectedOfferHash = marketplace.getOfferHash(
            InfinityMarketplace.Offer({
                maker: alice,
                nftContract: address(erc721),
                tokenId: TOKEN_ID,
                amount: 1,
                price: PRICE,
                offerType: InfinityMarketplace.OfferType.Sell
            })
        );
        emit OfferCreated(expectedOfferHash);

        marketplace.createOffer(
            address(erc721), TOKEN_ID, PRICE, 1, InfinityMarketplace.OfferType.Sell
        );
        vm.stopPrank();

        // Verify offer
        (
            address maker,
            address nftContract,
            uint256 tokenId,
            uint256 amount,
            uint256 price,
            InfinityMarketplace.OfferType offerType
        ) = marketplace.offers(expectedOfferHash);

        assertEq(maker, alice);
        assertEq(nftContract, address(erc721));
        assertEq(tokenId, TOKEN_ID);
        assertEq(amount, 1);
        assertEq(price, PRICE);
        assertEq(uint256(offerType), uint256(InfinityMarketplace.OfferType.Sell));
    }

    function test_AcceptBuyOffer() public {
        // Setup: Alice deposits NFT, Bob creates buy offer
        erc721.mint(alice, TOKEN_ID);
        vm.prank(alice);
        erc721.safeTransferFrom(alice, address(marketplace), TOKEN_ID);

        // Create buy offer
        bytes32 offerHash = marketplace.getOfferHash(
            InfinityMarketplace.Offer({
                maker: bob,
                nftContract: address(erc721),
                tokenId: TOKEN_ID,
                amount: 1,
                price: PRICE,
                offerType: InfinityMarketplace.OfferType.Buy
            })
        );

        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit OfferCreated(offerHash);

        marketplace.createOffer{value: PRICE}(
            address(erc721), TOKEN_ID, PRICE, 1, InfinityMarketplace.OfferType.Buy
        );
        vm.stopPrank();

        // Accept offer
        uint256 aliceInitialBalance = alice.balance;
        vm.prank(alice);
        marketplace.acceptOffer(offerHash);

        // Verify state changes
        assertEq(erc721.ownerOf(TOKEN_ID), bob);
        assertEq(alice.balance, aliceInitialBalance + PRICE);

        (uint256 balance,) = marketplace.deposits(alice, address(erc721), TOKEN_ID);
        assertEq(balance, 0);
    }

    function test_AcceptSellOffer() public {
        // Setup: Alice deposits NFT and creates sell offer
        erc721.mint(alice, TOKEN_ID);
        vm.startPrank(alice);
        erc721.safeTransferFrom(alice, address(marketplace), TOKEN_ID);

        bytes32 offerHash = marketplace.getOfferHash(
            InfinityMarketplace.Offer({
                maker: alice,
                nftContract: address(erc721),
                tokenId: TOKEN_ID,
                amount: 1,
                price: PRICE,
                offerType: InfinityMarketplace.OfferType.Sell
            })
        );
        marketplace.createOffer(
            address(erc721), TOKEN_ID, PRICE, 1, InfinityMarketplace.OfferType.Sell
        );
        vm.stopPrank();

        // Accept offer
        uint256 aliceInitialBalance = alice.balance;
        vm.prank(bob);
        marketplace.acceptOffer{value: PRICE}(offerHash);

        // Verify state changes
        assertEq(erc721.ownerOf(TOKEN_ID), bob);
        assertEq(alice.balance, aliceInitialBalance + PRICE);

        (uint256 balance,) = marketplace.deposits(alice, address(erc721), TOKEN_ID);
        assertEq(balance, 0);
    }

    function test_CancelBuyOffer() public {
        // Create buy offer
        vm.startPrank(bob);
        bytes32 offerHash = marketplace.getOfferHash(
            InfinityMarketplace.Offer({
                maker: bob,
                nftContract: address(erc721),
                tokenId: TOKEN_ID,
                amount: 1,
                price: PRICE,
                offerType: InfinityMarketplace.OfferType.Buy
            })
        );
        marketplace.createOffer{value: PRICE}(
            address(erc721), TOKEN_ID, PRICE, 1, InfinityMarketplace.OfferType.Buy
        );

        uint256 bobInitialBalance = bob.balance;

        vm.expectEmit(true, true, true, true);
        emit OfferCancelled(offerHash);

        marketplace.cancelOffer(offerHash);
        vm.stopPrank();

        // Verify state changes
        assertEq(bob.balance, bobInitialBalance + PRICE);

        (address maker,,,,,) = marketplace.offers(offerHash);
        assertEq(maker, address(0));
    }

    function test_CancelSellOffer() public {
        // Setup: Alice deposits NFT and creates sell offer
        erc721.mint(alice, TOKEN_ID);
        vm.startPrank(alice);
        erc721.safeTransferFrom(alice, address(marketplace), TOKEN_ID);

        bytes32 offerHash = marketplace.getOfferHash(
            InfinityMarketplace.Offer({
                maker: alice,
                nftContract: address(erc721),
                tokenId: TOKEN_ID,
                amount: 1,
                price: PRICE,
                offerType: InfinityMarketplace.OfferType.Sell
            })
        );
        marketplace.createOffer(
            address(erc721), TOKEN_ID, PRICE, 1, InfinityMarketplace.OfferType.Sell
        );

        vm.expectEmit(true, true, true, true);
        emit OfferCancelled(offerHash);

        marketplace.cancelOffer(offerHash);
        vm.stopPrank();

        // Verify state changes
        assertEq(erc721.ownerOf(TOKEN_ID), alice);

        (address maker,,,,,) = marketplace.offers(offerHash);
        assertEq(maker, address(0));
    }

    function test_RevertWhen_CreateBuyOfferWithoutPayment() public {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(InfinityMarketplace.MissingPayment.selector));
        marketplace.createOffer(
            address(erc721), TOKEN_ID, PRICE, 1, InfinityMarketplace.OfferType.Buy
        );
        vm.stopPrank();
    }

    function test_RevertWhen_CreateSellOfferWithoutDeposit() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(InfinityMarketplace.InsufficientDeposit.selector));
        marketplace.createOffer(
            address(erc721), TOKEN_ID, PRICE, 1, InfinityMarketplace.OfferType.Sell
        );
        vm.stopPrank();
    }

    function test_RevertWhen_CancelOfferByNonCreator() public {
        // Create buy offer as Bob
        vm.startPrank(bob);
        bytes32 offerHash = marketplace.getOfferHash(
            InfinityMarketplace.Offer({
                maker: bob,
                nftContract: address(erc721),
                tokenId: TOKEN_ID,
                amount: 1,
                price: PRICE,
                offerType: InfinityMarketplace.OfferType.Buy
            })
        );
        marketplace.createOffer{value: PRICE}(
            address(erc721), TOKEN_ID, PRICE, 1, InfinityMarketplace.OfferType.Buy
        );
        vm.stopPrank();

        // Try to cancel as Alice
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(InfinityMarketplace.NotOfferCreator.selector));
        marketplace.cancelOffer(offerHash);
        vm.stopPrank();
    }

    function test_RevertWhen_CreateOfferWithZeroPrice() public {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(InfinityMarketplace.InvalidPrice.selector));
        marketplace.createOffer(address(erc721), TOKEN_ID, 0, 1, InfinityMarketplace.OfferType.Buy);
        vm.stopPrank();
    }

    function test_RevertWhen_CreateOfferWithZeroAmount() public {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(InfinityMarketplace.InvalidAmount.selector));
        marketplace.createOffer{value: PRICE}(
            address(erc721), TOKEN_ID, PRICE, 0, InfinityMarketplace.OfferType.Buy
        );
        vm.stopPrank();
    }

    function test_RevertWhen_CreateOfferWithInvalidNFTContract() public {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(InfinityMarketplace.InvalidNFTContract.selector));
        marketplace.createOffer{value: PRICE}(
            address(0), TOKEN_ID, PRICE, 1, InfinityMarketplace.OfferType.Buy
        );
        vm.stopPrank();
    }
}
