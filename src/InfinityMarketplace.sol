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
    error ETHTransferFailed();

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
        uint256 price;
        OfferType offerType;
    }

    /// @notice Struct to store deposit details
    struct Deposit {
        uint256 balance;
        NFTType nftType;
    }

    /// @notice Mapping to track offers: contract => tokenId => offer details
    mapping(bytes32 => Offer) public offers;

    /// @notice Mapping to track deposited token balances: owner => contract => tokenId => amount
    mapping(address => mapping(address => mapping(uint256 => Deposit))) public deposits;

    /// @notice Event emitted when an NFT is deposited
    event Deposited(
        address indexed nftContract,
        uint256 indexed tokenId,
        address indexed depositor,
        uint256 amount,
        NFTType nftType
    );

    /// @notice Event emitted when an NFT is withdrawn
    event Withdrawn(
        address indexed nftContract,
        uint256 indexed tokenId,
        address indexed withdrawer,
        uint256 amount
    );

    /// @notice Event emitted when a buy offer is created
    event OfferCreated(bytes32 offerHash);

    /// @notice Event emitted when an offer is cancelled
    event OfferCancelled(bytes32 offerHash);

    /// @notice Event emitted when a trade is executed
    event OfferSettled(bytes32 offerHash);

    /**
     * @notice Creates a buy offer for a specific NFT
     * @param nftContract The address of the NFT contract
     * @param tokenId The ID of the token
     * @param amount The amount of tokens (1 for ERC721)
     */
    function createOffer(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        uint256 amount,
        OfferType offerType
    ) external payable {
        require(nftContract != address(0), InvalidNFTContract());
        require(amount != 0, InvalidAmount());
        require(price != 0, InvalidPrice());
        if (offerType == OfferType.Buy) {
            require(price == msg.value, MissingPayment());
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
            price: price,
            offerType: offerType
        });
        bytes32 offerHash = getOfferHash(offer);
        offers[offerHash] = offer;

        emit OfferCreated(offerHash);
    }

    /**
     * @notice Cancels an offer
     * @param offerHash The hash of the offer
     */
    function cancelOffer(bytes32 offerHash) external nonReentrant {
        Offer memory offer = offers[offerHash];
        require(offer.maker == msg.sender, NotOfferCreator());

        delete offers[offerHash];

        if (offer.offerType == OfferType.Buy) {
            _sendValue(offer.maker, offer.price);
        } else {
            Deposit memory deposit = deposits[offer.maker][offer.nftContract][offer.tokenId];
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
    function withdrawNFT(address nftContract, uint256 tokenId, uint256 amount) external {
        Deposit memory deposit = deposits[msg.sender][nftContract][tokenId];
        require(deposit.balance >= amount, InsufficientDeposit());

        delete deposits[msg.sender][nftContract][tokenId];

        if (deposit.nftType == NFTType.ERC721) {
            IERC721(nftContract).safeTransferFrom(address(this), msg.sender, tokenId);
        } else {
            IERC1155(nftContract).safeTransferFrom(address(this), msg.sender, tokenId, amount, "");
        }

        emit Withdrawn(nftContract, tokenId, msg.sender, deposit.balance);
    }

    /**
     * @notice Executes a trade by accepting an offer
     * @param offerHash The hash of the offer
     */
    function acceptOffer(bytes32 offerHash) external payable nonReentrant {
        Offer memory offer = offers[offerHash];

        if (offer.offerType == OfferType.Buy) {
            require(msg.value == 0, InvalidPrice());
            _acceptOffer(offer, msg.sender, offer.maker);
        } else {
            require(msg.value == offer.price, InvalidPrice());
            _acceptOffer(offer, offer.maker, msg.sender);
        }

        emit OfferSettled(offerHash);
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

        emit Deposited(msg.sender, tokenId, from, 1, NFTType.ERC721);

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

        emit Deposited(msg.sender, tokenId, from, value, NFTType.ERC1155);

        return IERC1155Receiver.onERC1155Received.selector;
    }

    function getOfferHash(Offer memory offer) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                offer.maker,
                offer.nftContract,
                offer.tokenId,
                offer.amount,
                offer.price,
                offer.offerType
            )
        );
    }

    function _acceptOffer(Offer memory offer, address seller, address buyer) internal {
        Deposit storage deposit = deposits[seller][offer.nftContract][offer.tokenId];
        require(deposit.balance >= offer.amount, InsufficientDeposit());

        deposit.balance -= offer.amount;

        _sendValue(seller, offer.price);
        _transferNFT(offer, buyer, deposit.nftType);
    }

    function _transferNFT(Offer memory offer, address to, NFTType nftType) internal {
        if (nftType == NFTType.ERC721) {
            IERC721(offer.nftContract).safeTransferFrom(address(this), to, offer.tokenId);
        } else {
            IERC1155(offer.nftContract).safeTransferFrom(
                address(this), to, offer.tokenId, offer.amount, ""
            );
        }
    }

    /**
     * @notice Safely sends ETH to an address
     * @param recipient The address to send ETH to
     * @param amount The amount of ETH to send
     */
    function _sendValue(address recipient, uint256 amount) internal {
        // slither-disable-next-line arbitrary-send-eth
        (bool success,) = recipient.call{value: amount}("");
        require(success, ETHTransferFailed());
    }
}
