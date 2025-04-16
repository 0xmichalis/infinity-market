// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title InfinityMarketplace
 * @notice A marketplace for trading ERC721 and ERC1155 tokens that have broken approval functions
 * @dev This marketplace allows users to deposit NFTs first and then create sell offers or match existing buy offers
 */
// slither-disable-next-line locked-ether
contract InfinityMarketplace is IERC721Receiver, IERC1155Receiver, ReentrancyGuard {
    /// @notice Marketplace errors
    error InvalidNFTContract();
    error InvalidAmount();
    error InvalidPrice();
    error MissingPayment();
    error UnnecessaryPayment();
    error InsufficientDeposit();
    error NotOfferCreator();
    error PaymentFailed();
    error OfferAlreadyExists();

    /// @notice Enum to represent the type of NFT
    enum NFTType {
        ERC721,
        ERC1155
    }

    /// @notice Enum to represent the type of offer
    enum OfferType {
        Buy,
        Sell
    }

    /// @notice Struct to store offer details
    struct Offer {
        address maker;
        address nftContract;
        uint256 tokenId;
        uint256 amount;
        uint256 pricePerUnit;
        OfferType offerType;
    }

    /// @notice Struct to store deposit details
    struct Deposit {
        uint256 balance;
        NFTType nftType;
    }

    /// @notice Event emitted when a buy offer is created
    event OfferCreated(bytes32 offerHash);

    /// @notice Event emitted when an offer is cancelled
    event OfferCancelled(bytes32 offerHash);

    /// @notice Event emitted when a trade is executed
    event OfferSettled(bytes32 offerHash, uint256 amount);

    /// @notice Mapping to track offers: contract => tokenId => offer details
    mapping(bytes32 => Offer) public offers;

    /// @notice Mapping to track deposited token balances: owner => contract => tokenId => amount
    mapping(address => mapping(address => mapping(uint256 => Deposit))) public deposits;

    /**
     * @notice Creates a buy offer for a specific NFT
     * @param nftContract The address of the NFT contract
     * @param tokenId The ID of the token
     * @param pricePerUnit The price per unit of the NFT
     * @param amount The amount of tokens (1 for ERC721)
     * @param offerType The type of offer (Buy or Sell)
     */
    function createOffer(
        address nftContract,
        uint256 tokenId,
        uint256 pricePerUnit,
        uint256 amount,
        OfferType offerType
    ) external payable {
        require(nftContract != address(0), InvalidNFTContract());
        require(amount != 0, InvalidAmount());
        require(pricePerUnit != 0, InvalidPrice());
        if (offerType == OfferType.Buy) {
            require(pricePerUnit * amount == msg.value, MissingPayment());
        } else {
            require(msg.value == 0, UnnecessaryPayment());
            require(
                deposits[msg.sender][nftContract][tokenId].balance >= amount, InsufficientDeposit()
            );
        }

        Offer memory offer = Offer({
            maker: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            amount: amount,
            pricePerUnit: pricePerUnit,
            offerType: offerType
        });
        bytes32 offerHash = getOfferHash(offer);
        // Require canceling an existing offer before recreating it.
        // This can happen if the user wants to change the amount of the offer.
        // TODO: Create a function specific to this use case to avoid having
        // to cancel and recreate the offer.
        require(offers[offerHash].maker == address(0), OfferAlreadyExists());
        offers[offerHash] = offer;

        emit OfferCreated(offerHash);
    }

    /**
     * @notice Cancels an offer
     * @param offerHash The hash of the offer
     */
    // TODO: Consider whether NFT transfers should happen here.
    // May be best to provide a cancelOfferAndWithdrawNFT function that does both.
    function cancelOffer(bytes32 offerHash) external nonReentrant {
        Offer memory offer = offers[offerHash];
        require(offer.maker == msg.sender, NotOfferCreator());

        delete offers[offerHash];

        if (offer.offerType == OfferType.Buy) {
            _sendValue(offer.maker, offer.pricePerUnit * offer.amount);
        } else {
            Deposit storage deposit = deposits[offer.maker][offer.nftContract][offer.tokenId];
            deposit.balance -= offer.amount;
            if (deposit.nftType == NFTType.ERC721) {
                IERC721(offer.nftContract).safeTransferFrom(
                    address(this), offer.maker, offer.tokenId
                );
            } else {
                IERC1155(offer.nftContract).safeTransferFrom(
                    address(this), offer.maker, offer.tokenId, offer.amount, ""
                );
            }
        }

        emit OfferCancelled(offerHash);
    }

    /**
     * @notice Withdraws deposited NFTs
     * @param nftContract The address of the NFT contract
     * @param tokenId The ID of the token
     * @param amount The amount of tokens to withdraw. 1 for ERC721, amount for ERC1155
     */
    // TODO: Should not work once a sell offer is created?
    function withdrawNFT(address nftContract, uint256 tokenId, uint256 amount) external {
        Deposit memory deposit = deposits[msg.sender][nftContract][tokenId];
        require(deposit.balance >= amount, InsufficientDeposit());

        if (deposit.balance == amount) {
            delete deposits[msg.sender][nftContract][tokenId];
        } else {
            // we just checked this above
            unchecked {
                deposits[msg.sender][nftContract][tokenId].balance = deposit.balance - amount;
            }
        }

        if (deposit.nftType == NFTType.ERC721) {
            IERC721(nftContract).safeTransferFrom(address(this), msg.sender, tokenId);
        } else {
            IERC1155(nftContract).safeTransferFrom(address(this), msg.sender, tokenId, amount, "");
        }
    }

    /**
     * @notice Executes a trade by accepting an offer
     * @param offerHash The hash of the offer
     * @param amount The amount of tokens to accept
     */
    function acceptOffer(bytes32 offerHash, uint256 amount) external payable nonReentrant {
        Offer storage offer = offers[offerHash];

        if (offer.offerType == OfferType.Buy) {
            require(msg.value == 0, UnnecessaryPayment());
            _acceptOffer(offer, offerHash, msg.sender, offer.maker, amount);
        } else {
            require(msg.value == offer.pricePerUnit * amount, InvalidPrice());
            _acceptOffer(offer, offerHash, offer.maker, msg.sender, amount);
        }

        emit OfferSettled(offerHash, amount);
    }

    /**
     * @notice Implements IERC165
     */
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC721Receiver).interfaceId
            || interfaceId == type(IERC1155Receiver).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    /**
     * @notice Implements IERC721Receiver
     *
     * NOTE this is callable by anyone so malicious users can create fake deposits
     * but at least they cannot fake the nftContract. End users should always verify
     * they are using the correct contract before interacting with this contract
     */
    function onERC721Received(address, address from, uint256 tokenId, bytes calldata)
        external
        override
        returns (bytes4)
    {
        deposits[from][msg.sender][tokenId] = Deposit({balance: 1, nftType: NFTType.ERC721});

        return IERC721Receiver.onERC721Received.selector;
    }

    /**
     * @notice Implements IERC1155Receiver
     *
     * NOTE this is callable by anyone so malicious users can create fake deposits
     * but at least they cannot fake the nftContract. End users should always verify
     * they are using the correct contract before interacting with this contract
     */
    function onERC1155BatchReceived(
        address,
        address from,
        uint256[] calldata tokenIds,
        uint256[] calldata values,
        bytes calldata data
    ) external override returns (bytes4) {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            onERC1155Received(msg.sender, from, tokenIds[i], values[i], data);
        }

        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    /**
     * @notice Implements IERC1155Receiver
     *
     * NOTE this is callable by anyone so malicious users can create fake deposits
     * but at least they cannot fake the nftContract. End users should always verify
     * they are using the correct contract before interacting with this contract
     */
    function onERC1155Received(
        address,
        address from,
        uint256 tokenId,
        uint256 value,
        bytes calldata
    ) public override returns (bytes4) {
        deposits[from][msg.sender][tokenId] = Deposit({balance: value, nftType: NFTType.ERC1155});

        return IERC1155Receiver.onERC1155Received.selector;
    }

    /**
     * @notice Returns the hash of an offer
     * @param offer The offer to hash
     * @return hash The hash of the offer
     * NOTE: Changing the amount of the offer for ERC1155 does not change the hash.
     *       This is intentional to allow partial fills.
     */
    function getOfferHash(Offer memory offer) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                offer.maker, offer.nftContract, offer.tokenId, offer.pricePerUnit, offer.offerType
            )
        );
    }

    function _acceptOffer(
        Offer storage offer,
        bytes32 offerHash,
        address seller,
        address buyer,
        uint256 amount
    ) internal {
        Deposit storage deposit = deposits[seller][offer.nftContract][offer.tokenId];
        uint256 depositBalance = deposit.balance;
        require(depositBalance >= amount, InsufficientDeposit());
        uint256 offerAmount = offer.amount;
        require(offerAmount >= amount, InvalidAmount());

        unchecked {
            // we just checked these above
            deposit.balance = depositBalance - amount;
            offer.amount = offerAmount - amount;
        }

        _sendValue(seller, offer.pricePerUnit * amount);
        _transferNFT(offer, buyer, deposit.nftType, amount);

        if (offerAmount - amount == 0) {
            delete offers[offerHash];
        }
    }

    function _transferNFT(Offer storage offer, address to, NFTType nftType, uint256 amount)
        internal
    {
        if (nftType == NFTType.ERC721) {
            IERC721(offer.nftContract).safeTransferFrom(address(this), to, offer.tokenId);
        } else {
            IERC1155(offer.nftContract).safeTransferFrom(
                address(this), to, offer.tokenId, amount, ""
            );
        }
    }

    function _sendValue(address recipient, uint256 amount) internal {
        // slither-disable-next-line arbitrary-send-eth
        (bool success,) = recipient.call{value: amount}("");
        require(success, PaymentFailed());
    }
}
