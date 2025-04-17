// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {InfinityMarketplace} from "../src/InfinityMarketplace.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {MockERC1155} from "./mocks/MockERC1155.sol";
import {MockContractWithoutReceive} from "./mocks/MockContractWithoutReceive.sol";

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

    function setUp() public {
        marketplace = new InfinityMarketplace();
        erc721 = new MockERC721();
        erc1155 = new MockERC1155();

        // Fund test accounts
        vm.deal(alice, INITIAL_BALANCE);
        vm.deal(bob, INITIAL_BALANCE);
    }

    function test_SupportsInterface() public view {
        // Test ERC721 receiver interface
        assertTrue(marketplace.supportsInterface(0x150b7a02));
        // Test ERC1155 receiver interface
        assertTrue(marketplace.supportsInterface(0x4e2312e0));
        // Test non-supported interface
        assertFalse(marketplace.supportsInterface(0x12345678));
    }

    function test_DepositERC721() public {
        // Mint token to alice
        erc721.mint(alice, TOKEN_ID);

        // Deposit as alice
        vm.prank(alice);
        erc721.safeTransferFrom(alice, address(marketplace), TOKEN_ID);

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
        vm.prank(alice);
        erc1155.safeTransferFrom(alice, address(marketplace), TOKEN_ID, TOKEN_AMOUNT, "");

        // Verify deposit
        (uint256 balance, InfinityMarketplace.NFTType nftType) =
            marketplace.deposits(alice, address(erc1155), TOKEN_ID);
        assertEq(balance, TOKEN_AMOUNT);
        assertEq(uint256(nftType), uint256(InfinityMarketplace.NFTType.ERC1155));
    }

    function test_DepositERC1155Batch() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = TOKEN_ID;
        ids[1] = TOKEN_ID + 1;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = TOKEN_AMOUNT;
        amounts[1] = TOKEN_AMOUNT * 2;

        // Mint tokens to alice
        erc1155.mint(alice, ids[0], amounts[0]);
        erc1155.mint(alice, ids[1], amounts[1]);

        // Deposit as alice
        vm.startPrank(alice);
        erc1155.safeBatchTransferFrom(alice, address(marketplace), ids, amounts, "");
        vm.stopPrank();

        // Verify deposits
        for (uint256 i = 0; i < ids.length; i++) {
            (uint256 balance, InfinityMarketplace.NFTType nftType) =
                marketplace.deposits(alice, address(erc1155), ids[i]);
            assertEq(balance, amounts[i]);
            assertEq(uint256(nftType), uint256(InfinityMarketplace.NFTType.ERC1155));
        }
    }

    function test_MultipleERC1155Deposits() public {
        // First deposit of 5 tokens
        vm.startPrank(alice);
        erc1155.mint(alice, TOKEN_ID, 5);
        erc1155.safeTransferFrom(alice, address(marketplace), TOKEN_ID, 5, "");

        // Verify first deposit
        (uint256 balanceAfterFirst, InfinityMarketplace.NFTType nftType) =
            marketplace.deposits(alice, address(erc1155), TOKEN_ID);
        assertEq(balanceAfterFirst, 5);
        assertEq(uint256(nftType), uint256(InfinityMarketplace.NFTType.ERC1155));

        // Second deposit of 3 more tokens
        erc1155.mint(alice, TOKEN_ID, 3);
        erc1155.safeTransferFrom(alice, address(marketplace), TOKEN_ID, 3, "");
        vm.stopPrank();

        // The deposits mapping should be updated to:
        // balanceAfterFirst + 3 = 8 tokens total
        (uint256 finalBalance, InfinityMarketplace.NFTType finalType) =
            marketplace.deposits(alice, address(erc1155), TOKEN_ID);
        assertEq(finalBalance, 8, "Deposit balance should be sum of both deposits");
        assertEq(uint256(finalType), uint256(InfinityMarketplace.NFTType.ERC1155));

        // Verify actual token balances
        assertEq(erc1155.balanceOf(alice, TOKEN_ID), 0, "Alice should have no tokens left");
        assertEq(
            erc1155.balanceOf(address(marketplace), TOKEN_ID),
            8,
            "Marketplace should have all tokens"
        );
    }

    function test_CreateBuyOffer() public {
        vm.startPrank(bob);

        bytes32 expectedOfferHash = marketplace.getOfferHash(
            InfinityMarketplace.Offer({
                maker: bob,
                nftContract: address(erc721),
                tokenId: TOKEN_ID,
                amount: 1,
                pricePerUnit: PRICE,
                offerType: InfinityMarketplace.OfferType.Buy
            })
        );

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
            uint256 pricePerUnit,
            InfinityMarketplace.OfferType offerType
        ) = marketplace.offers(expectedOfferHash);

        assertEq(maker, bob);
        assertEq(nftContract, address(erc721));
        assertEq(tokenId, TOKEN_ID);
        assertEq(amount, 1);
        assertEq(pricePerUnit, PRICE);
        assertEq(uint256(offerType), uint256(InfinityMarketplace.OfferType.Buy));
    }

    function test_CreateSellOffer() public {
        // First deposit NFT
        erc721.mint(alice, TOKEN_ID);
        vm.startPrank(alice);
        erc721.safeTransferFrom(alice, address(marketplace), TOKEN_ID);

        bytes32 expectedOfferHash = marketplace.getOfferHash(
            InfinityMarketplace.Offer({
                maker: alice,
                nftContract: address(erc721),
                tokenId: TOKEN_ID,
                amount: 1,
                pricePerUnit: PRICE,
                offerType: InfinityMarketplace.OfferType.Sell
            })
        );

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
            uint256 pricePerUnit,
            InfinityMarketplace.OfferType offerType
        ) = marketplace.offers(expectedOfferHash);

        assertEq(maker, alice);
        assertEq(nftContract, address(erc721));
        assertEq(tokenId, TOKEN_ID);
        assertEq(amount, 1);
        assertEq(pricePerUnit, PRICE);
        assertEq(uint256(offerType), uint256(InfinityMarketplace.OfferType.Sell));
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

    function test_RevertWhen_CreateSellOfferWithPayment() public {
        // First deposit NFT
        erc721.mint(alice, TOKEN_ID);
        vm.startPrank(alice);
        erc721.safeTransferFrom(alice, address(marketplace), TOKEN_ID);

        // Try to create sell offer with payment
        vm.expectRevert(abi.encodeWithSelector(InfinityMarketplace.UnnecessaryPayment.selector));
        marketplace.createOffer{value: PRICE}(
            address(erc721), TOKEN_ID, PRICE, 1, InfinityMarketplace.OfferType.Sell
        );
        vm.stopPrank();
    }

    function test_RevertWhen_CreateSellOfferWithInsufficientDeposit() public {
        // Setup: Alice deposits 1 ERC1155 token but creates offer for 2
        erc1155.mint(alice, TOKEN_ID, 1);
        vm.startPrank(alice);
        erc1155.safeTransferFrom(alice, address(marketplace), TOKEN_ID, 1, "");

        vm.expectRevert(abi.encodeWithSelector(InfinityMarketplace.InsufficientDeposit.selector));
        marketplace.createOffer(
            address(erc1155), TOKEN_ID, PRICE, 2, InfinityMarketplace.OfferType.Sell
        );
        vm.stopPrank();
    }

    function test_RevertWhen_CreateDuplicateOffer() public {
        // Create initial buy offer
        vm.startPrank(bob);
        marketplace.createOffer{value: PRICE * 2}(
            address(erc721), TOKEN_ID, PRICE, 2, InfinityMarketplace.OfferType.Buy
        );

        // Try to create the same offer again - this can cause loss of funds
        // if not handled correctly.
        vm.expectRevert(abi.encodeWithSelector(InfinityMarketplace.OfferAlreadyExists.selector));
        marketplace.createOffer{value: PRICE}(
            address(erc721), TOKEN_ID, PRICE, 1, InfinityMarketplace.OfferType.Buy
        );
        vm.stopPrank();
    }

    function test_CreateCollectionOffer() public {
        vm.startPrank(bob);

        bytes32 expectedOfferHash = marketplace.getOfferHash(
            InfinityMarketplace.Offer({
                maker: bob,
                nftContract: address(erc721),
                tokenId: 0, // zero indicates a collection offer
                amount: 5,
                pricePerUnit: PRICE,
                offerType: InfinityMarketplace.OfferType.Buy
            })
        );

        marketplace.createCollectionOffer{value: PRICE * 5}(address(erc721), 5, PRICE);
        vm.stopPrank();

        // Verify offer
        (
            address maker,
            address nftContract,
            uint256 tokenId,
            uint256 amount,
            uint256 pricePerUnit,
            InfinityMarketplace.OfferType offerType
        ) = marketplace.offers(expectedOfferHash);

        assertEq(maker, bob);
        assertEq(nftContract, address(erc721));
        assertEq(tokenId, 0);
        assertEq(amount, 5);
        assertEq(pricePerUnit, PRICE);
        assertEq(uint256(offerType), uint256(InfinityMarketplace.OfferType.Buy));
    }

    function test_RevertWhen_CreateCollectionOfferWithoutPayment() public {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(InfinityMarketplace.MissingPayment.selector));
        marketplace.createCollectionOffer(address(erc721), 5, PRICE);
        vm.stopPrank();
    }

    function test_RevertWhen_CreateCollectionOfferWithInvalidContract() public {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(InfinityMarketplace.InvalidNFTContract.selector));
        marketplace.createCollectionOffer{value: PRICE * 5}(address(0), 5, PRICE);
        vm.stopPrank();
    }

    function test_RevertWhen_CreateCollectionOfferWithZeroAmount() public {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(InfinityMarketplace.InvalidAmount.selector));
        marketplace.createCollectionOffer{value: 0}(address(erc721), 0, PRICE);
        vm.stopPrank();
    }

    function test_RevertWhen_CreateCollectionOfferWithZeroPrice() public {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(InfinityMarketplace.InvalidPrice.selector));
        marketplace.createCollectionOffer{value: 0}(address(erc721), 5, 0);
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
                pricePerUnit: PRICE,
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

    function test_RevertWhen_CancelOfferAndWithdrawNFTByNonCreator() public {
        // Create buy offer as Bob
        vm.startPrank(bob);
        bytes32 offerHash = marketplace.getOfferHash(
            InfinityMarketplace.Offer({
                maker: bob,
                nftContract: address(erc721),
                tokenId: TOKEN_ID,
                amount: 1,
                pricePerUnit: PRICE,
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
        marketplace.cancelOfferAndWithdrawNFT(offerHash);
        vm.stopPrank();
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
                pricePerUnit: PRICE,
                offerType: InfinityMarketplace.OfferType.Buy
            })
        );
        marketplace.createOffer{value: PRICE}(
            address(erc721), TOKEN_ID, PRICE, 1, InfinityMarketplace.OfferType.Buy
        );

        uint256 bobInitialBalance = bob.balance;

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
                pricePerUnit: PRICE,
                offerType: InfinityMarketplace.OfferType.Sell
            })
        );
        marketplace.createOffer(
            address(erc721), TOKEN_ID, PRICE, 1, InfinityMarketplace.OfferType.Sell
        );

        // Cancel offer
        marketplace.cancelOffer(offerHash);
        vm.stopPrank();

        // Verify offer is removed but NFT remains in marketplace
        assertEq(erc721.ownerOf(TOKEN_ID), address(marketplace));
        (uint256 balance,) = marketplace.deposits(alice, address(erc721), TOKEN_ID);
        assertEq(balance, 1);
        (address maker,,,,,) = marketplace.offers(offerHash);
        assertEq(maker, address(0));
    }

    function test_CancelSellOfferAndWithdrawERC721() public {
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
                pricePerUnit: PRICE,
                offerType: InfinityMarketplace.OfferType.Sell
            })
        );
        marketplace.createOffer(
            address(erc721), TOKEN_ID, PRICE, 1, InfinityMarketplace.OfferType.Sell
        );

        // Cancel offer and withdraw
        marketplace.cancelOfferAndWithdrawNFT(offerHash);
        vm.stopPrank();

        // Verify state changes
        assertEq(erc721.ownerOf(TOKEN_ID), alice);
        (uint256 balance,) = marketplace.deposits(alice, address(erc721), TOKEN_ID);
        assertEq(balance, 0);
        (address maker,,,,,) = marketplace.offers(offerHash);
        assertEq(maker, address(0));
    }

    function test_CancelSellOfferERC1155() public {
        // Alice deposits 10 ERC1155 tokens
        vm.startPrank(alice);
        erc1155.mint(alice, TOKEN_ID, 10);
        erc1155.setApprovalForAll(address(marketplace), true);
        erc1155.safeTransferFrom(alice, address(marketplace), TOKEN_ID, 10, "");

        // Create sell offer for 5 tokens
        bytes32 offerHash = marketplace.getOfferHash(
            InfinityMarketplace.Offer({
                maker: alice,
                nftContract: address(erc1155),
                tokenId: TOKEN_ID,
                amount: 5,
                pricePerUnit: PRICE,
                offerType: InfinityMarketplace.OfferType.Sell
            })
        );
        marketplace.createOffer(
            address(erc1155), TOKEN_ID, PRICE, 5, InfinityMarketplace.OfferType.Sell
        );

        // Cancel offer
        marketplace.cancelOffer(offerHash);
        vm.stopPrank();

        // Verify deposit balance remains unchanged
        (uint256 balance, InfinityMarketplace.NFTType nftType) =
            marketplace.deposits(alice, address(erc1155), TOKEN_ID);
        assertEq(uint256(nftType), uint256(InfinityMarketplace.NFTType.ERC1155));
        assertEq(balance, 10); // All tokens should still be in deposit

        // Verify offer is deleted
        (
            address offerMaker,
            address offerNftContract,
            uint256 offerTokenId,
            uint256 offerAmount,
            uint256 offerPrice,
            InfinityMarketplace.OfferType offerType
        ) = marketplace.offers(offerHash);
        assertEq(offerMaker, address(0));
        assertEq(offerNftContract, address(0));
        assertEq(offerTokenId, 0);
        assertEq(offerAmount, 0);
        assertEq(offerPrice, 0);
        assertEq(uint8(offerType), 0);

        // Verify tokens remain in marketplace
        assertEq(erc1155.balanceOf(alice, TOKEN_ID), 0);
        assertEq(erc1155.balanceOf(address(marketplace), TOKEN_ID), 10);
    }

    function test_CancelSellOfferAndWithdrawERC1155() public {
        // Alice deposits 10 ERC1155 tokens
        vm.startPrank(alice);
        erc1155.mint(alice, TOKEN_ID, 10);
        erc1155.setApprovalForAll(address(marketplace), true);
        erc1155.safeTransferFrom(alice, address(marketplace), TOKEN_ID, 10, "");

        // Create sell offer for 5 tokens
        bytes32 offerHash = marketplace.getOfferHash(
            InfinityMarketplace.Offer({
                maker: alice,
                nftContract: address(erc1155),
                tokenId: TOKEN_ID,
                amount: 5,
                pricePerUnit: PRICE,
                offerType: InfinityMarketplace.OfferType.Sell
            })
        );
        marketplace.createOffer(
            address(erc1155), TOKEN_ID, PRICE, 5, InfinityMarketplace.OfferType.Sell
        );

        // Cancel offer and withdraw
        marketplace.cancelOfferAndWithdrawNFT(offerHash);
        vm.stopPrank();

        // Verify deposit balance is updated
        (uint256 balance, InfinityMarketplace.NFTType nftType) =
            marketplace.deposits(alice, address(erc1155), TOKEN_ID);
        assertEq(uint256(nftType), uint256(InfinityMarketplace.NFTType.ERC1155));
        assertEq(balance, 5); // Should have 5 tokens remaining

        // Verify offer is deleted
        (
            address offerMaker,
            address offerNftContract,
            uint256 offerTokenId,
            uint256 offerAmount,
            uint256 offerPrice,
            InfinityMarketplace.OfferType offerType
        ) = marketplace.offers(offerHash);
        assertEq(offerMaker, address(0));
        assertEq(offerNftContract, address(0));
        assertEq(offerTokenId, 0);
        assertEq(offerAmount, 0);
        assertEq(offerPrice, 0);
        assertEq(uint8(offerType), 0);

        // Verify tokens are split between Alice and marketplace
        assertEq(erc1155.balanceOf(alice, TOKEN_ID), 5); // Tokens from cancelled offer
        assertEq(erc1155.balanceOf(address(marketplace), TOKEN_ID), 5); // Remaining deposit
    }

    function test_RevertWhen_CancelOfferAndWithdrawOnBuyOffer() public {
        // Create buy offer
        vm.startPrank(bob);
        bytes32 offerHash = marketplace.getOfferHash(
            InfinityMarketplace.Offer({
                maker: bob,
                nftContract: address(erc721),
                tokenId: TOKEN_ID,
                amount: 1,
                pricePerUnit: PRICE,
                offerType: InfinityMarketplace.OfferType.Buy
            })
        );
        marketplace.createOffer{value: PRICE}(
            address(erc721), TOKEN_ID, PRICE, 1, InfinityMarketplace.OfferType.Buy
        );

        // Try to cancel and withdraw - should fail
        vm.expectRevert(abi.encodeWithSelector(InfinityMarketplace.InvalidOfferType.selector));
        marketplace.cancelOfferAndWithdrawNFT(offerHash);
        vm.stopPrank();
    }

    function test_withdrawNFT() public {
        // Mint NFT to Alice
        erc721.mint(alice, TOKEN_ID);

        // Alice deposits NFT
        vm.startPrank(alice);
        erc721.safeTransferFrom(alice, address(marketplace), TOKEN_ID);

        // Verify deposit exists
        (uint256 balance, InfinityMarketplace.NFTType nftType) =
            marketplace.deposits(alice, address(erc721), TOKEN_ID);
        assertEq(balance, 1);
        assertEq(uint256(nftType), uint256(InfinityMarketplace.NFTType.ERC721));

        // Withdraw NFT
        marketplace.withdrawNFT(address(erc721), TOKEN_ID, 1);
        vm.stopPrank();

        // Verify NFT is back with Alice and deposit is cleared
        assertEq(erc721.ownerOf(TOKEN_ID), alice);
        (uint256 finalBalance,) = marketplace.deposits(alice, address(erc721), TOKEN_ID);
        assertEq(finalBalance, 0);
    }

    function test_PartialWithdrawERC1155() public {
        // Mint tokens to alice
        erc1155.mint(alice, TOKEN_ID, TOKEN_AMOUNT);

        // Deposit as alice
        vm.startPrank(alice);
        erc1155.safeTransferFrom(alice, address(marketplace), TOKEN_ID, TOKEN_AMOUNT, "");

        // Verify initial deposit
        (uint256 initialBalance, InfinityMarketplace.NFTType nftType) =
            marketplace.deposits(alice, address(erc1155), TOKEN_ID);
        assertEq(initialBalance, TOKEN_AMOUNT);
        assertEq(uint256(nftType), uint256(InfinityMarketplace.NFTType.ERC1155));

        // Withdraw half of the tokens
        uint256 withdrawAmount = TOKEN_AMOUNT / 2;
        marketplace.withdrawNFT(address(erc1155), TOKEN_ID, withdrawAmount);
        vm.stopPrank();

        // Verify remaining deposit
        (uint256 remainingBalance, InfinityMarketplace.NFTType nftTypeAfter) =
            marketplace.deposits(alice, address(erc1155), TOKEN_ID);
        assertEq(remainingBalance, TOKEN_AMOUNT - withdrawAmount);
        assertEq(uint256(nftTypeAfter), uint256(InfinityMarketplace.NFTType.ERC1155));

        // Verify alice's token balance
        assertEq(erc1155.balanceOf(alice, TOKEN_ID), withdrawAmount);
    }

    function test_RevertWhen_WithdrawInvalidAmount() public {
        // Mint tokens to alice
        erc1155.mint(alice, TOKEN_ID, TOKEN_AMOUNT);

        // Deposit as alice
        vm.startPrank(alice);
        erc1155.safeTransferFrom(alice, address(marketplace), TOKEN_ID, TOKEN_AMOUNT, "");

        // Try to withdraw more than deposited
        vm.expectRevert(abi.encodeWithSelector(InfinityMarketplace.InsufficientDeposit.selector));
        marketplace.withdrawNFT(address(erc1155), TOKEN_ID, TOKEN_AMOUNT + 1);
        vm.stopPrank();
    }

    function test_RevertWhen_WithdrawFromWrongNFTType() public {
        // First deposit ERC721
        erc721.mint(alice, TOKEN_ID);
        vm.startPrank(alice);
        erc721.safeTransferFrom(alice, address(marketplace), TOKEN_ID);

        // Try to withdraw as if it was ERC1155
        vm.expectRevert(abi.encodeWithSelector(InfinityMarketplace.InsufficientDeposit.selector));
        marketplace.withdrawNFT(address(erc721), TOKEN_ID, 2);
        vm.stopPrank();
    }

    function test_RevertWhen_AcceptOfferWithInvalidAmount() public {
        // Setup: Alice deposits NFT and creates sell offer
        erc1155.mint(alice, TOKEN_ID, 2);
        vm.startPrank(alice);
        erc1155.safeTransferFrom(alice, address(marketplace), TOKEN_ID, 2, "");

        bytes32 offerHash = marketplace.getOfferHash(
            InfinityMarketplace.Offer({
                maker: alice,
                nftContract: address(erc1155),
                tokenId: TOKEN_ID,
                amount: 1,
                pricePerUnit: PRICE,
                offerType: InfinityMarketplace.OfferType.Sell
            })
        );
        marketplace.createOffer(
            address(erc1155), TOKEN_ID, PRICE, 1, InfinityMarketplace.OfferType.Sell
        );
        vm.stopPrank();

        // Try to accept with invalid amount
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(InfinityMarketplace.InvalidAmount.selector));
        marketplace.acceptOffer{value: PRICE * 2}(offerHash, 2);
        vm.stopPrank();
    }

    function test_RevertWhen_AcceptBuyOfferWithPayment() public {
        // Setup: Alice deposits NFT, Bob creates buy offer
        erc721.mint(alice, TOKEN_ID);
        vm.startPrank(alice);
        erc721.safeTransferFrom(alice, address(marketplace), TOKEN_ID);
        vm.stopPrank();

        // Create buy offer
        vm.startPrank(bob);
        bytes32 offerHash = marketplace.getOfferHash(
            InfinityMarketplace.Offer({
                maker: bob,
                nftContract: address(erc721),
                tokenId: TOKEN_ID,
                amount: 1,
                pricePerUnit: PRICE,
                offerType: InfinityMarketplace.OfferType.Buy
            })
        );
        marketplace.createOffer{value: PRICE}(
            address(erc721), TOKEN_ID, PRICE, 1, InfinityMarketplace.OfferType.Buy
        );
        vm.stopPrank();

        // Try to accept buy offer with payment (should not send ETH)
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(InfinityMarketplace.UnnecessaryPayment.selector));
        marketplace.acceptOffer{value: PRICE}(offerHash, 1);
        vm.stopPrank();
    }

    function test_RevertWhen_AcceptSellOfferWithWrongPayment() public {
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
                pricePerUnit: PRICE,
                offerType: InfinityMarketplace.OfferType.Sell
            })
        );
        marketplace.createOffer(
            address(erc721), TOKEN_ID, PRICE, 1, InfinityMarketplace.OfferType.Sell
        );
        vm.stopPrank();

        // Try to accept sell offer with wrong payment amount
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(InfinityMarketplace.InvalidPrice.selector));
        marketplace.acceptOffer{value: PRICE / 2}(offerHash, 1);
        vm.stopPrank();
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
                pricePerUnit: PRICE,
                offerType: InfinityMarketplace.OfferType.Buy
            })
        );

        vm.prank(bob);
        marketplace.createOffer{value: PRICE}(
            address(erc721), TOKEN_ID, PRICE, 1, InfinityMarketplace.OfferType.Buy
        );

        // Accept offer
        uint256 aliceInitialBalance = alice.balance;
        vm.prank(alice);
        marketplace.acceptOffer(offerHash, 1);

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
                pricePerUnit: PRICE,
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
        marketplace.acceptOffer{value: PRICE}(offerHash, 1);

        // Verify state changes
        assertEq(erc721.ownerOf(TOKEN_ID), bob);
        assertEq(alice.balance, aliceInitialBalance + PRICE);

        (uint256 balance,) = marketplace.deposits(alice, address(erc721), TOKEN_ID);
        assertEq(balance, 0);
    }

    function test_RevertWhen_AcceptOfferWithInsufficientDeposit() public {
        // Setup: Alice deposits 1 ERC1155 token
        erc1155.mint(alice, TOKEN_ID, 1);
        vm.startPrank(alice);
        erc1155.safeTransferFrom(alice, address(marketplace), TOKEN_ID, 1, "");
        vm.stopPrank();

        // Bob creates buy offer for 2 tokens
        bytes32 offerHash = marketplace.getOfferHash(
            InfinityMarketplace.Offer({
                maker: bob,
                nftContract: address(erc1155),
                tokenId: TOKEN_ID,
                amount: 2,
                pricePerUnit: PRICE,
                offerType: InfinityMarketplace.OfferType.Buy
            })
        );
        vm.prank(bob);
        marketplace.createOffer{value: PRICE * 2}(
            address(erc1155), TOKEN_ID, PRICE, 2, InfinityMarketplace.OfferType.Buy
        );

        // Try to accept offer - should fail because Alice only has 1 token
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(InfinityMarketplace.InsufficientDeposit.selector));
        marketplace.acceptOffer(offerHash, 2);
    }

    function test_AcceptBuyOfferERC1155() public {
        // Setup: Alice deposits ERC1155, Bob creates buy offer
        erc1155.mint(alice, TOKEN_ID, TOKEN_AMOUNT);
        vm.prank(alice);
        erc1155.safeTransferFrom(alice, address(marketplace), TOKEN_ID, TOKEN_AMOUNT, "");

        uint256 offerAmount = 2;
        // Create buy offer
        bytes32 offerHash = marketplace.getOfferHash(
            InfinityMarketplace.Offer({
                maker: bob,
                nftContract: address(erc1155),
                tokenId: TOKEN_ID,
                amount: offerAmount,
                pricePerUnit: PRICE,
                offerType: InfinityMarketplace.OfferType.Buy
            })
        );
        vm.prank(bob);
        marketplace.createOffer{value: PRICE * offerAmount}(
            address(erc1155), TOKEN_ID, PRICE, offerAmount, InfinityMarketplace.OfferType.Buy
        );

        // Accept offer
        uint256 aliceInitialBalance = alice.balance;
        vm.prank(alice);
        marketplace.acceptOffer(offerHash, offerAmount);

        // Verify state changes
        assertEq(erc1155.balanceOf(bob, TOKEN_ID), offerAmount, "ERC1155 balance not transferred");
        assertEq(
            alice.balance, aliceInitialBalance + PRICE * offerAmount, "ETH balance not transferred"
        );

        (uint256 balance,) = marketplace.deposits(alice, address(erc1155), TOKEN_ID);
        assertEq(balance, TOKEN_AMOUNT - offerAmount, "Deposit not updated");
    }

    function test_RevertWhen_PaymentFailsOnAcceptOffer() public {
        MockContractWithoutReceive mockContractWithoutReceive = new MockContractWithoutReceive();

        // Mint NFT to the contract that can't receive ETH
        erc721.mint(address(mockContractWithoutReceive), TOKEN_ID);

        // Contract deposits NFT
        vm.startPrank(address(mockContractWithoutReceive));
        erc721.safeTransferFrom(address(mockContractWithoutReceive), address(marketplace), TOKEN_ID);

        // Create sell offer from contract that can't receive ETH
        bytes32 offerHash = marketplace.getOfferHash(
            InfinityMarketplace.Offer({
                maker: address(mockContractWithoutReceive),
                nftContract: address(erc721),
                tokenId: TOKEN_ID,
                amount: 1,
                pricePerUnit: PRICE,
                offerType: InfinityMarketplace.OfferType.Sell
            })
        );
        marketplace.createOffer(
            address(erc721), TOKEN_ID, PRICE, 1, InfinityMarketplace.OfferType.Sell
        );
        vm.stopPrank();

        // Try to accept offer - should fail because contract can't receive ETH payment
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(InfinityMarketplace.PaymentFailed.selector));
        marketplace.acceptOffer{value: PRICE}(offerHash, 1);
        vm.stopPrank();

        // Verify state remains unchanged
        assertEq(erc721.ownerOf(TOKEN_ID), address(marketplace), "NFT ownership changed");
        (uint256 balance,) =
            marketplace.deposits(address(mockContractWithoutReceive), address(erc721), TOKEN_ID);
        assertEq(balance, 1, "Deposit changed");
        (address maker,,,,,) = marketplace.offers(offerHash);
        assertEq(maker, address(mockContractWithoutReceive), "Offer was removed");
    }

    function test_RevertWhen_AcceptOfferAfterWithdrawal() public {
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
                pricePerUnit: PRICE,
                offerType: InfinityMarketplace.OfferType.Sell
            })
        );
        marketplace.createOffer(
            address(erc721), TOKEN_ID, PRICE, 1, InfinityMarketplace.OfferType.Sell
        );

        // Alice withdraws the NFT
        marketplace.withdrawNFT(address(erc721), TOKEN_ID, 1);
        vm.stopPrank();

        // Bob tries to accept the offer
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(InfinityMarketplace.InsufficientDeposit.selector));
        marketplace.acceptOffer{value: PRICE}(offerHash, 1);

        // Verify state remains unchanged
        assertEq(erc721.ownerOf(TOKEN_ID), alice, "NFT ownership should remain with Alice");
        (uint256 balance,) = marketplace.deposits(alice, address(erc721), TOKEN_ID);
        assertEq(balance, 0, "Deposit should remain empty");
        (address maker,,,,,) = marketplace.offers(offerHash);
        assertEq(maker, alice, "Offer should still exist");
    }

    function test_RevertWhen_AcceptOfferAfterPartialWithdrawalERC1155() public {
        // Setup: Alice deposits 10 ERC1155 tokens and creates sell offer for 8
        vm.startPrank(alice);
        erc1155.mint(alice, TOKEN_ID, 10);
        erc1155.safeTransferFrom(alice, address(marketplace), TOKEN_ID, 10, "");

        bytes32 offerHash = marketplace.getOfferHash(
            InfinityMarketplace.Offer({
                maker: alice,
                nftContract: address(erc1155),
                tokenId: TOKEN_ID,
                amount: 8,
                pricePerUnit: PRICE,
                offerType: InfinityMarketplace.OfferType.Sell
            })
        );
        marketplace.createOffer(
            address(erc1155), TOKEN_ID, PRICE, 8, InfinityMarketplace.OfferType.Sell
        );

        // Alice withdraws 3 tokens, leaving only 7 (less than offer amount)
        marketplace.withdrawNFT(address(erc1155), TOKEN_ID, 3);
        vm.stopPrank();

        // Bob tries to accept the offer
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(InfinityMarketplace.InsufficientDeposit.selector));
        marketplace.acceptOffer{value: PRICE * 8}(offerHash, 8);

        // Verify state remains unchanged
        assertEq(erc1155.balanceOf(alice, TOKEN_ID), 3, "Alice should have withdrawn tokens");
        assertEq(
            erc1155.balanceOf(address(marketplace), TOKEN_ID),
            7,
            "Marketplace should have remaining tokens"
        );
        (uint256 balance,) = marketplace.deposits(alice, address(erc1155), TOKEN_ID);
        assertEq(balance, 7, "Deposit should reflect withdrawal");
        (address maker,,,,,) = marketplace.offers(offerHash);
        assertEq(maker, alice, "Offer should still exist");

        uint256 aliceInitialBalance = alice.balance;

        // Bob tries to accept 6 tokens
        vm.prank(bob);
        marketplace.acceptOffer{value: PRICE * 6}(offerHash, 6);

        // Verify updated state
        assertEq(erc1155.balanceOf(bob, TOKEN_ID), 6, "ERC1155 balance not transferred");
        assertEq(alice.balance, aliceInitialBalance + PRICE * 6, "ETH balance not transferred");
        (balance,) = marketplace.deposits(alice, address(erc1155), TOKEN_ID);
        assertEq(balance, 1, "Deposit should reflect settled offer");
    }

    function test_AcceptCollectionOffer() public {
        // Setup: Create collection offer from Bob
        vm.startPrank(bob);
        bytes32 offerHash = marketplace.getOfferHash(
            InfinityMarketplace.Offer({
                maker: bob,
                nftContract: address(erc721),
                tokenId: 0,
                amount: 5,
                pricePerUnit: PRICE,
                offerType: InfinityMarketplace.OfferType.Buy
            })
        );
        marketplace.createCollectionOffer{value: PRICE * 5}(address(erc721), 5, PRICE);
        vm.stopPrank();

        // Setup: Alice deposits multiple NFTs
        vm.startPrank(alice);
        for (uint256 i = 1; i <= 3; i++) {
            erc721.mint(alice, i);
            erc721.safeTransferFrom(alice, address(marketplace), i);
        }

        // Accept offer for both tokens at once
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;

        uint256 aliceInitialBalance = alice.balance;
        marketplace.acceptCollectionOffer(offerHash, tokenIds, amounts);
        vm.stopPrank();

        // Verify state changes
        assertEq(erc721.ownerOf(1), bob);
        assertEq(erc721.ownerOf(2), bob);
        assertEq(erc721.ownerOf(3), address(marketplace));
        assertEq(alice.balance, aliceInitialBalance + PRICE * 2);

        // Verify deposits are updated
        for (uint256 i = 1; i <= 2; i++) {
            (uint256 balance,) = marketplace.deposits(alice, address(erc721), i);
            assertEq(balance, 0);
        }
        (uint256 balance3,) = marketplace.deposits(alice, address(erc721), 3);
        assertEq(balance3, 1);

        // Verify offer is updated
        (,,, uint256 remainingAmount,,) = marketplace.offers(offerHash);
        assertEq(remainingAmount, 3, "Remaining amount should be 3 (5 initial - 2 accepted)");
    }

    function test_AcceptCollectionOfferERC1155() public {
        // Setup: Create collection offer from Bob
        vm.startPrank(bob);
        bytes32 offerHash = marketplace.getOfferHash(
            InfinityMarketplace.Offer({
                maker: bob,
                nftContract: address(erc1155),
                tokenId: 0,
                amount: 10,
                pricePerUnit: PRICE,
                offerType: InfinityMarketplace.OfferType.Buy
            })
        );
        marketplace.createCollectionOffer{value: PRICE * 10}(address(erc1155), 10, PRICE);
        vm.stopPrank();

        // Setup: Alice deposits multiple ERC1155s
        vm.startPrank(alice);
        erc1155.mint(alice, 1, 5);
        erc1155.mint(alice, 2, 8);
        erc1155.safeTransferFrom(alice, address(marketplace), 1, 5, "");
        erc1155.safeTransferFrom(alice, address(marketplace), 2, 8, "");

        // Accept offer for both tokens at once
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 3;
        amounts[1] = 4;

        uint256 aliceInitialBalance = alice.balance;
        marketplace.acceptCollectionOffer(offerHash, tokenIds, amounts);
        vm.stopPrank();

        // Verify state changes
        assertEq(erc1155.balanceOf(bob, 1), 3);
        assertEq(erc1155.balanceOf(bob, 2), 4);
        assertEq(alice.balance, aliceInitialBalance + PRICE * 7);

        // Verify deposits are updated
        (uint256 balance1,) = marketplace.deposits(alice, address(erc1155), 1);
        assertEq(balance1, 2);
        (uint256 balance2,) = marketplace.deposits(alice, address(erc1155), 2);
        assertEq(balance2, 4);

        // Verify offer is updated
        (,,, uint256 remainingAmount,,) = marketplace.offers(offerHash);
        assertEq(remainingAmount, 3, "Remaining amount should be 3 (10 initial - (3 + 4) accepted)");
    }

    function test_RevertWhen_AcceptCollectionOfferWithMismatchedArrays() public {
        // Setup: Create collection offer
        vm.startPrank(bob);
        bytes32 offerHash = marketplace.getOfferHash(
            InfinityMarketplace.Offer({
                maker: bob,
                nftContract: address(erc721),
                tokenId: 0,
                amount: 5,
                pricePerUnit: PRICE,
                offerType: InfinityMarketplace.OfferType.Buy
            })
        );
        marketplace.createCollectionOffer{value: PRICE * 5}(address(erc721), 5, PRICE);
        vm.stopPrank();

        // Try to accept with mismatched arrays
        vm.startPrank(alice);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        vm.expectRevert(abi.encodeWithSelector(InfinityMarketplace.InvalidAmounts.selector));
        marketplace.acceptCollectionOffer(offerHash, tokenIds, amounts);
        vm.stopPrank();
    }

    function test_RevertWhen_AcceptCollectionOfferOnSellOffer() public {
        // Setup: Create sell offer
        erc721.mint(alice, TOKEN_ID);
        vm.startPrank(alice);
        erc721.safeTransferFrom(alice, address(marketplace), TOKEN_ID);

        bytes32 offerHash = marketplace.getOfferHash(
            InfinityMarketplace.Offer({
                maker: alice,
                nftContract: address(erc721),
                tokenId: TOKEN_ID,
                amount: 1,
                pricePerUnit: PRICE,
                offerType: InfinityMarketplace.OfferType.Sell
            })
        );
        marketplace.createOffer(
            address(erc721), TOKEN_ID, PRICE, 1, InfinityMarketplace.OfferType.Sell
        );
        vm.stopPrank();

        // Try to accept sell offer using acceptCollectionOffer
        vm.startPrank(bob);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = TOKEN_ID;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        vm.expectRevert(abi.encodeWithSelector(InfinityMarketplace.InvalidOfferType.selector));
        marketplace.acceptCollectionOffer(offerHash, tokenIds, amounts);
        vm.stopPrank();
    }
}
