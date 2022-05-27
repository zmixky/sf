//SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

interface IToken is IERC721 {
    function isFirstSaleAdmin(address sender) external view returns (bool);

    function mintTo(address recipient, uint256 id) external;
}

contract FS is Pausable, Multicall {
    struct ConfinesForTimeData {
        uint256 startTimestampIsSeconds;
        uint256 endTimestampIsSeconds;
    }

    enum ConfinesForTokensKind {
        NONE,
        INTERVAL_CONFINES,
        TOKEN_LIST_CONFINES
    }

    struct IntervalConfinesForTokensData {
        uint256 startOfInterval;
        uint256 endOfInterval;
    }

    struct TokenListConfinesForTokensData {
        BitMaps.BitMap tokenMap;
    }

    struct SignConfinesForCustomersData {
        address key;
        uint128 kind;
    }

    //rename
    struct TokenConfinesForCustomersData {
        address token;
    }

    //rename
    struct TokenListConfinesForCustomersData {
        uint8 count;
        mapping(uint8 => address) tokenMap;
    }

    enum SaleKind {
        NONE,
        PURCHASE,
        DUTCH_AUCTION
    }

    struct PurchaseData {
        uint256 price;
    }

    struct DutchAuctionData {
        uint256 startPrice;
        uint256 endPrice;
        uint256 tickSizeInSeconds;
    }

    struct SaleData {
        SaleKind kind;
        address payToken;
        address payRecipient;
        PurchaseData purchase;
        DutchAuctionData dutchAuction;
    }

    uint256 public feeAmount;
    address public feeRecipient;

    IToken public token;

    ConfinesForTokensKind public confinesKindForTokens;

    bool public isSignConfinesForCustomers;
    bool public isTokenConfinesForCustomers;
    bool public isTokenListConfinesForCustomers;

    ConfinesForTimeData private _confinesForTime;

    IntervalConfinesForTokensData private _intervalConfinesForTokens;
    TokenListConfinesForTokensData private _tokenListConfinesForTokens;

    SignConfinesForCustomersData private _signConfinesForCustomers;
    TokenConfinesForCustomersData private _tokenConfinesForCustomers;
    TokenListConfinesForCustomersData private _tokenListConfinesForCustomers;

    SaleData private _sale;

    modifier onlyFirstSaleAdmin() {
        if (!token.isFirstSaleAdmin(_msgSender())) {
            revert(""); //todo
        }
        _;
    }

    constructor(
        IToken token_,
        address feeRecipient_,
        uint256 feeAmount_
    ) {
        token = token_;

        feeRecipient = feeRecipient_;
        feeAmount = feeAmount_;
    }

    function priceOf(uint256 timestampIsSeconds)
        public
        view
        whenNotPaused
        returns (uint256)
    {
        if (_sale.kind == SaleKind.NONE) {
            revert(""); //todo
        }

        if (_sale.kind == SaleKind.PURCHASE) {
            return _sale.purchase.price;
        }

        if (_sale.kind == SaleKind.DUTCH_AUCTION) {
            uint256 tick = (timestampIsSeconds -
                _confinesForTime.startTimestampIsSeconds) /
                _sale.dutchAuction.tickSizeInSeconds;
            uint256 tickCount = (_confinesForTime.endTimestampIsSeconds -
                _confinesForTime.startTimestampIsSeconds) /
                _sale.dutchAuction.tickSizeInSeconds;

            return
                _sale.dutchAuction.startPrice -
                ((_sale.dutchAuction.startPrice - _sale.dutchAuction.endPrice) *
                    tick) /
                tickCount;
        }
    }

    function pause() external onlyFirstSaleAdmin {
        _pause();
    }

    function unpause() external onlyFirstSaleAdmin {
        _unpause();
    }

    function setConfinesForTime(
        uint256 startTimestampIsSeconds,
        uint256 endTimestampIsSeconds
    ) external onlyFirstSaleAdmin {
        _confinesForTime.startTimestampIsSeconds = startTimestampIsSeconds;
        _confinesForTime.endTimestampIsSeconds = endTimestampIsSeconds;
    }

    function setIntervalConfinesForTokens(
        uint256 startOfInterval,
        uint256 endOfInterval
    ) external onlyFirstSaleAdmin {
        delete _tokenListConfinesForTokens;

        _intervalConfinesForTokens.startOfInterval = startOfInterval;
        _intervalConfinesForTokens.endOfInterval = endOfInterval;
    }

    function setTokenListConfinesForTokens(uint256[] calldata tokenList)
        external
        onlyFirstSaleAdmin
    {
        delete _intervalConfinesForTokens;
        delete _tokenListConfinesForTokens;

        for (uint256 i = 0; i < tokenList.length; ++i) {
            BitMaps.set(_tokenListConfinesForTokens.tokenMap, tokenList[i]);
        }
    }

    function setConfinesForCustomer(
        address key_,
        uint128 kind_,
        address token_,
        address[] calldata tokenList_
    ) external onlyFirstSaleAdmin {
        if (key_ != address(0)) {
            _signConfinesForCustomers.key = key_;
            _signConfinesForCustomers.kind = kind_;
        } else {
            delete _signConfinesForCustomers;
        }

        if (token_ != address(0)) {
            _tokenConfinesForCustomers.token = token_;
        } else {
            delete _tokenConfinesForCustomers;
        }

        //todo
        _tokenListConfinesForCustomers.count = uint8(tokenList_.length);
        for (uint256 i = 0; i < tokenList_.length; ++i) {
            _tokenListConfinesForCustomers.tokenMap[uint8(i)] = tokenList_[i];
        }
    }

    function setPurchase(
        address payToken,
        address payRecipient,
        uint256 price
    ) external onlyFirstSaleAdmin {
        delete _sale.dutchAuction;

        _sale.kind = SaleKind.PURCHASE;
        _sale.payToken = payToken;
        _sale.payRecipient = payRecipient;
        _sale.purchase.price = price;
    }

    function setDutchAuction(
        address payToken,
        address payRecipient,
        uint256 startPrice,
        uint256 endPrice,
        uint256 tickSizeInSeconds
    ) external onlyFirstSaleAdmin {
        delete _sale.purchase;

        _sale.kind = SaleKind.DUTCH_AUCTION;
        _sale.payToken = payToken;
        _sale.payRecipient = payRecipient;
        _sale.dutchAuction.startPrice = startPrice;
        _sale.dutchAuction.endPrice = endPrice;
        _sale.dutchAuction.tickSizeInSeconds = tickSizeInSeconds;
    }

    function buy(
        uint256 id,
        uint256 checkId,
        bytes memory sign
    ) external payable whenNotPaused {
        address sender = _msgSender();

        _checkConfinesForTime(block.timestamp);
        _checkConfinesForTokens(id);
        _checkConfinesForCustomers(sender, id, checkId, sign);

        _buy(block.timestamp, sender, id, msg.value);
    }

    function _checkConfinesForTime(uint256 timestampIsSeconds) private view {
        if (
            _confinesForTime.startTimestampIsSeconds != 0 &&
            timestampIsSeconds < _confinesForTime.startTimestampIsSeconds
        ) {
            revert(""); //todo
        }

        if (
            _confinesForTime.endTimestampIsSeconds != 0 &&
            _confinesForTime.endTimestampIsSeconds <= timestampIsSeconds
        ) {
            revert(""); //todo
        }
    }

    function _checkConfinesForTokens(uint256 id) private view {
        if (
            ConfinesForTokensKind.INTERVAL_CONFINES == confinesKindForTokens &&
            (id < _intervalConfinesForTokens.startOfInterval ||
                _intervalConfinesForTokens.endOfInterval < id)
        ) {
            revert(""); //todo
        }

        if (
            ConfinesForTokensKind.TOKEN_LIST_CONFINES ==
            confinesKindForTokens &&
            !BitMaps.get(_tokenListConfinesForTokens.tokenMap, id)
        ) {
            revert(""); //todo
        }
    }

    function _checkConfinesForCustomers(
        address sender,
        uint256 id,
        uint256 checkId,
        bytes memory sign
    ) private view {
        if (
            isSignConfinesForCustomers &&
            !SignatureChecker.isValidSignatureNow(
                _signConfinesForCustomers.key,
                _signHash(sender),
                sign
            )
        ) {
            revert(""); //todo
        }

        if (
            isTokenConfinesForCustomers &&
            IERC721(_tokenConfinesForCustomers.token).ownerOf(checkId) != sender
        ) {
            revert(""); //todo
        }

        if (
            isTokenListConfinesForCustomers &&
            _tokenListConfinesForCustomers.count != 0
        ) {
            for (
                uint256 i = 0;
                i < uint256(_tokenListConfinesForCustomers.count);
                ++i
            ) {
                if (
                    IERC721(_tokenListConfinesForCustomers.tokenMap[uint8(i)])
                        .ownerOf(id) != sender
                ) {
                    revert(""); //todo
                }
            }
        }
    }

    function _signHash(address sender) private view returns (bytes32) {
        return
            keccak256(
                abi.encodeWithSignature(
                    "SignHash(address,address,uin128)",
                    sender,
                    address(token),
                    _signConfinesForCustomers.kind
                )
            );
    }

    function _buy(
        uint256 timestampIsSeconds,
        address sender,
        uint256 id,
        uint256 coinValue
    ) private {
        if (0 < feeAmount) {
            if (coinValue < feeAmount) {
                revert(""); //todo
            }

            _sendCoin(feeRecipient, feeAmount);
            coinValue -= feeAmount;
        }

        uint256 price = priceOf(timestampIsSeconds);
        if (_sale.payToken != address(0)) {
            _sendCoin(_sale.payRecipient, price);
            coinValue -= price;
        } else {
            IERC20(_sale.payToken).transferFrom(
                sender,
                _sale.payRecipient,
                price
            );
        }

        if (coinValue != 0) {
            revert("");
        }

        token.mintTo(sender, id);
    }

    function _sendCoin(address recipient, uint256 amount) private {
        (bool success, ) = recipient.call{value: amount}("");

        if (!success) {
            revert(""); //todo
        }
    }
}
