// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface NFT721{
    function royaltyInfo(uint256 _tokenId, uint256 _salePrice) external view returns(address receiver, uint256 royaltyAmount);
    function ownerOf(uint256 tokenId) external view returns (address);
    function getApproved(uint256 tokenId) external view returns (address);
    function totalSupply() external view returns(uint256);
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external ;
}
  
interface NFT1155 {
    function royaltyInfo(uint256 _tokenId, uint256 _salePrice) external view returns(address receiver, uint256 royaltyAmount);
    function balanceOf(address account, uint256 id) external view returns (uint256);
    function isApprovedForAll(address account, address operator) external view returns (bool);
    function ownerOf(uint256 tokenId) external view  returns (address);
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external;
}

contract NFTMarketplace is Ownable, ReentrancyGuard {

    using Counters for Counters.Counter;      
    Counters.Counter public _listingIds1155;
    uint8 public commission = 2;
    
    mapping(uint128 => Listing1155) public idToListing1155;
    mapping(address => mapping(uint256 => MarketItem721)) public listNfts;
    mapping(address => mapping(uint256 => Offer)) public offerNfts;
    mapping(address => mapping(uint256 => tokenDetails721)) public auctionNfts;

    NFT721 private BERC721;   
    NFT1155 private BERC1155;
    IERC20 private BERC20;


    constructor(address _erc721, address _erc1155, address _erc20) {
        BERC721 = NFT721(_erc721);
        BERC1155 = NFT1155(_erc1155);
        BERC20 = IERC20(_erc20);
    }


    struct tokenDetails721 {
        address seller;
        uint128 price;
        uint32 duration;
        uint128 maxBid;
        address maxBidUser;
        bool isActive;
        uint128[] bidAmounts;
        address[] users;
    }


    struct MarketItem721 {
        address payable seller;
        uint128 price;
        bool sold;
    }


    struct Listing1155 {
        address nft;
        address seller;
        address[] buyer;
        uint128 tokenId;
        uint128 amount;
        uint128 price;
        uint128 tokensAvailable;
        bool privateListing;
        bool completed;
        uint listingId;
    }


    struct Offer {
        address[] offerers;
        uint128[] offerAmounts;
        address owner;
        bool isAccepted;
    }


    event TokenListed1155(                                                         
        address indexed seller, 
        uint128 indexed tokenId, 
        uint128 amount, 
        uint128 pricePerToken, 
        address[] privateBuyer, 
        bool privateSale, 
        uint indexed listingId
    );


    event TokenSold1155(
        address seller, 
        address buyer, 
        uint128 tokenId, 
        uint128 amount, 
        uint128 pricePerToken, 
        bool privateSale
    );


    event ListingDeleted1155(
        uint indexed listingId
    );


    function getRoyalties721(uint256 tokenId, uint256 price)
        private
        view
        returns (address receiver, uint256 royaltyAmount)
    {
        (receiver, royaltyAmount) = BERC721.royaltyInfo(tokenId, price);
        if (receiver == address(0) || royaltyAmount == 0) {
            return (address(0), 0);
        }
        return (receiver, royaltyAmount);
    }


    function getRoyalties1155(uint256 tokenId, uint256 price)
        private
        view
        returns (address receiver, uint256 royaltyAmount)
    {
        (receiver, royaltyAmount) = BERC1155.royaltyInfo(tokenId, price);
        if (receiver == address(0) || royaltyAmount == 0) {
            return (address(0), 0);
        }
        return (receiver, royaltyAmount);
    }


    function makeOffer(address _nft, uint256 _tokenId, uint128 _offer) external nonReentrant  {

    require(BERC20.allowance(msg.sender, address(this)) >= _offer, "token not approved");

    Offer storage offer = offerNfts[_nft][_tokenId];

        if (offer.offerers.length == 0) {

            offerNfts[_nft][_tokenId] = Offer({

                offerers: new address[](0),
                offerAmounts: new uint128[](0),
                owner: IERC721(_nft).ownerOf(_tokenId),
                isAccepted: false
            });

            offer.offerers.push(msg.sender);
            offer.offerAmounts.push(_offer);


        } else {

       
        offer.offerers.push(msg.sender);
        offer.offerAmounts.push(_offer);

        }

    }


    function acceptOffer(address _nft, uint256 _tokenId, address _offerer) external nonReentrant {

        require(IERC721(_nft).ownerOf(_tokenId) == msg.sender, "Only the owner is allowed to accept offer");
        Offer memory offer = offerNfts[_nft][_tokenId];
        require(!offer.isAccepted, "Already completed");
        require(msg.sender == offer.owner, "Caller is not the seller");

        uint256 lastIndex = offer.offerers.length - 1;
        uint128 offerAmount;

        for (uint256 i; i <= lastIndex; i++) {
            if(offer.offerers[i] == _offerer) {
                offerAmount = offer.offerAmounts[i];
            }
        }

        require(BERC20.allowance(_offerer, address(this)) >= offerAmount, "token not approved");
        offer.isAccepted = true;

        if (address(_nft) == address(BERC721)) {
            (address royaltyReceiver, uint256 royaltyAmount) = getRoyalties721(_tokenId, offerAmount);
            BERC20.transferFrom(_offerer, offer.owner,  ((offerAmount - royaltyAmount)*(100 - commission))/100);
            BERC20.transferFrom(_offerer, address(this),  ((offerAmount - royaltyAmount)*(commission))/100);
            BERC20.transferFrom(_offerer, royaltyReceiver, royaltyAmount);
        } else {
            BERC20.transferFrom(_offerer, offer.owner,  (offerAmount*(100 - commission))/100);
            BERC20.transferFrom(_offerer, address(this),  (offerAmount*(commission))/100);
        }

        IERC721(_nft).safeTransferFrom(
            offer.owner,
            _offerer,
            _tokenId
        );
    }


    function rejectOffer(address _nft, uint256 _tokenId) external nonReentrant {
        Offer memory offer = offerNfts[_nft][_tokenId];
        require(msg.sender == offer.owner, "You can't reject offers to this token");
        require(!offer.isAccepted, "Offer already accepted or rejected");
        delete offerNfts[_nft][_tokenId];
    }


    function fetchOffers(address _nft, uint256 _tokenId) public view returns (Offer memory) {
        Offer memory offer = offerNfts[_nft][_tokenId];
        return offer;
    }


    function createMarketItem721(address _nft, uint128 _tokenId, uint128 _price)
        external 
        nonReentrant
    {
        require(
            IERC721(_nft).getApproved(_tokenId) == address(this),
           "Market is not approved"
        );
        IERC721 nft = IERC721(_nft);
        require(nft.ownerOf(_tokenId) == msg.sender, "not nft owner");
        listNfts[_nft][_tokenId] = MarketItem721({
            seller: payable(msg.sender),
            price: _price,
            sold: false
        });

    }


    function createMarketSale721(address _nft, uint256 _tokenId)
        external
        payable
        nonReentrant
    {

        require(
            IERC721(_nft).getApproved(_tokenId) == address(this),
           "Market is not approved, cannot sell."
        );
        IERC721 nft = IERC721(_nft);
        MarketItem721 storage listedNft = listNfts[_nft][_tokenId];
        require(msg.sender != listedNft.seller, "Seller can't be buyer");
        require(
        msg.value >= listedNft.price,
            "Please submit the asking price in order to complete the purchase"
        );

        listedNft.sold = true;
        if (address(nft) == address(BERC721)) {

            (address royaltyReceiver, uint256 royaltyAmount) = getRoyalties721(
            _tokenId,
            msg.value);

            (bool success, ) = listedNft.seller.call{value: ((listedNft.price - royaltyAmount)*(100 - commission))/100}("");
            require(success,"Unable to transfer funds to seller");
            (bool success0, ) = royaltyReceiver.call{value: royaltyAmount}("");
            require(success0,"Unable to transfer funds to royalty reciever"); 
        } else {

            (bool success, ) = listedNft.seller.call{value: (listedNft.price*(100 - commission))/100}("");
            require(success,"Unable to transfer funds to seller");
        }

        nft.transferFrom(listedNft.seller, msg.sender, _tokenId);
    }


    function cancelMarketItem721(address _nft, uint256 _tokenId)
        external
        nonReentrant
    {
        MarketItem721 storage listedNft  = listNfts[_nft][_tokenId];
        require(!listedNft.sold, "Already sold");
        require(listedNft.seller == msg.sender, "not listed owner");
        delete listNfts[_nft][_tokenId];
    }


    function fetchMarketItem721(address _nft, uint256 _tokenId) public view returns (MarketItem721 memory) {
        MarketItem721 memory listedNft  = listNfts[_nft][_tokenId];
        return listedNft;
    }


    function createTokenAuction721(
        address _nft,
        uint128 _tokenId,
        uint128 _price,  // In wei and in token
        uint32 _duration
    ) external {

        require(
            IERC721(_nft).getApproved(_tokenId) == address(this),
           "Market is not approved"
        );

        require(msg.sender == IERC721(_nft).ownerOf(_tokenId), "Not the owner of tokenId");
        require(_price > 0, "Price should be more than 0");
        require(_duration > block.timestamp, "Invalid duration value");
        auctionNfts[_nft][_tokenId] = tokenDetails721({

            seller: msg.sender,
            price: uint128(_price),
            duration: _duration,
            maxBid: 0,
            maxBidUser: address(0),
            isActive: true,
            bidAmounts: new uint128[](0),
            users: new address[](0)
        });
        
    }


    function bid721(address _nft, uint256 _tokenId, uint128 _amount) external nonReentrant {
        tokenDetails721 storage auction = auctionNfts[_nft][_tokenId];
        require(_amount >= auction.price, "Bid less than price");
        require(BERC20.allowance(msg.sender, address(this)) >= _amount, "token not approved");
        require(auction.isActive, "auction not active");
        require(auction.duration > block.timestamp, "Deadline already passed");

        if (auction.bidAmounts.length == 0) {
            auction.maxBid = _amount;
            auction.maxBidUser = msg.sender;
        } else {
            uint256 lastIndex = auction.bidAmounts.length - 1;
            require(auction.bidAmounts[lastIndex] < _amount, "Current max bid is higher than your bid");
            auction.maxBid = _amount;
            auction.maxBidUser = msg.sender;
        }

        auction.users.push(msg.sender);
        auction.bidAmounts.push(_amount);
    }


    function executeSale721(address _nft, uint256 _tokenId) external nonReentrant {
        tokenDetails721 storage auction = auctionNfts[_nft][_tokenId];
        require(
            IERC721(_nft).getApproved(_tokenId) == address(this),
           "Market is not approved, cannot sell."
        );

        require(auction.maxBidUser == msg.sender || msg.sender == auction.seller, "You can't buy");
        require(auction.duration <= block.timestamp, "Deadline did not pass yet");
        require(auction.isActive, "auction not active");
        auction.isActive = false;

        if (address(_nft) == address(BERC721)) {
            require(BERC20.allowance(auction.maxBidUser, address(this)) >= auction.maxBid, "token not approved by bidder");
            (address royaltyReceiver, uint256 royaltyAmount) = getRoyalties721(
                _tokenId,
                auction.maxBid
            );

            BERC20.transferFrom(auction.maxBidUser, auction.seller,  ((auction.maxBid - royaltyAmount)*(100 - commission))/100);
            BERC20.transferFrom(auction.maxBidUser, address(this),  ((auction.maxBid - royaltyAmount)*(commission))/100);
            BERC20.transferFrom(auction.maxBidUser, royaltyReceiver, royaltyAmount);
            BERC721.safeTransferFrom(
                auction.seller,
                auction.maxBidUser,
                _tokenId
            );
        } else {
            require(BERC20.allowance(auction.maxBidUser, address(this)) >= auction.maxBid, "token not approved by bidder");
            BERC20.transferFrom(auction.maxBidUser, auction.seller,  ((auction.maxBid)*(100 - commission))/100);
            BERC20.transferFrom(auction.maxBidUser, address(this),  ((auction.maxBid)*(commission))/100);
            IERC721(_nft).safeTransferFrom(
                auction.seller,
                auction.maxBidUser,
                _tokenId
            );
        }
    }
    

    function cancelAuction721(address _nft, uint256 _tokenId) external nonReentrant {
        tokenDetails721 storage auction = auctionNfts[_nft][_tokenId];
        require(auction.seller == msg.sender, "Not seller");
        require(auction.isActive, "auction not active");
        auction.isActive = false;
        delete  auctionNfts[_nft][_tokenId];
    }


    function getTokenAuctionDetails721(address _nft, uint256 _tokenId) public view returns (tokenDetails721 memory) {
        tokenDetails721 memory auction = auctionNfts[_nft][_tokenId];
        return auction;
    }

    receive() external payable {}

    function listToken1155(address _nft, uint128 tokenId, uint128 amount, uint128 price, address[] memory privateBuyer) public nonReentrant returns(uint256) {
        require(amount > 0, "Amount must be greater than 0!");
        require(IERC1155(_nft).balanceOf(msg.sender, tokenId) >= amount, "Caller must own given token!");
        require(IERC1155(_nft).isApprovedForAll(msg.sender, address(this)), "Contract must be approved!");

        bool privateListing = privateBuyer.length>0;
        _listingIds1155.increment();
        uint256 listingId = _listingIds1155.current();
        idToListing1155[uint128(listingId)] = Listing1155(_nft, msg.sender, privateBuyer, tokenId, amount, price, amount, privateListing, false, _listingIds1155.current());

        emit TokenListed1155(msg.sender, tokenId, amount, price, privateBuyer, privateListing, _listingIds1155.current());
        return _listingIds1155.current();
    }


    function purchaseToken1155(uint128 listingId, uint128 amount) public payable nonReentrant {
        if(idToListing1155[listingId].privateListing == true) {
            bool whitelisted = false;
            for(uint i=0; i<idToListing1155[listingId].buyer.length; i++){
                if(idToListing1155[listingId].buyer[i] == msg.sender) {
                    whitelisted = true;
                }
            }
            require(whitelisted == true, "Sale is private!");
        }

        require(msg.sender != idToListing1155[listingId].seller, "Can't buy your own tokens!");
        require(msg.value >= idToListing1155[listingId].price * amount, "Insufficient funds!");
        require(IERC1155(idToListing1155[listingId].nft).balanceOf(idToListing1155[listingId].seller, idToListing1155[listingId].tokenId) >= amount, "Seller doesn't have enough tokens!");
        require(idToListing1155[listingId].completed == false, "Listing not available anymore!");
        require(idToListing1155[listingId].tokensAvailable >= amount, "Not enough tokens left!");

        idToListing1155[listingId].tokensAvailable -= amount;

        if(idToListing1155[listingId].privateListing == false){
            idToListing1155[listingId].buyer.push(msg.sender);
        }

        if(idToListing1155[listingId].tokensAvailable == 0) {
            idToListing1155[listingId].completed = true;
        }

        if(address(idToListing1155[listingId].nft) == address(BERC1155)) {
            (address royaltyReceiver, uint256 royaltyAmount) = getRoyalties1155(
                idToListing1155[listingId].tokenId,
                idToListing1155[listingId].price
            );

            (bool success, ) = idToListing1155[listingId].seller.call{value: ((idToListing1155[listingId].price - royaltyAmount)*amount*(100 - commission))/100}("");
                require(success, "Unable to transfer funds to seller");

            (bool success0, ) = royaltyReceiver.call{value: royaltyAmount*amount}("");
                require(success0, "Unable to transfer funds to royalty reciever");    

            BERC1155.safeTransferFrom(idToListing1155[listingId].seller, msg.sender, idToListing1155[listingId].tokenId, amount, "");

            emit TokenSold1155(
                idToListing1155[listingId].seller,
                msg.sender,
                idToListing1155[listingId].tokenId,
                amount,
                idToListing1155[listingId].price,
                idToListing1155[listingId].privateListing
            );
        } else {
            (bool success, ) = idToListing1155[listingId].seller.call{value: ((idToListing1155[listingId].price)*amount*(100 - commission))/100}("");
                require(success, "Unable to transfer funds to seller");
            IERC1155(idToListing1155[listingId].nft).safeTransferFrom(idToListing1155[listingId].seller, msg.sender, idToListing1155[listingId].tokenId, amount, "");
        }

    }


    function deleteListing1155(uint128 _listingId) external nonReentrant{
        require(msg.sender == idToListing1155[_listingId].seller, "Not caller's listing!");
        require(idToListing1155[_listingId].completed == false, "Listing not available!");
        idToListing1155[_listingId].completed = true;

        emit ListingDeleted1155(_listingId);
    }

    function viewListing1155(uint128 _listId) public view returns(Listing1155 memory) {
        Listing1155 memory listing = idToListing1155[_listId];
        return listing;
    }


    function withdraw(uint128 _amount) public payable onlyOwner {
        require (_amount < address(this).balance, "Try a smaller amount");
	    (bool success, ) = payable(msg.sender).call{value: _amount}("");
		require(success, "Unable to transfer funds");
	}


    function withdrawAnyToken(address _token, uint128 _amount) public onlyOwner {
        require (IERC20(_token).balanceOf(address(this)) > _amount, "Try a smaller amount");
        IERC20(_token).transferFrom(address(this), msg.sender, _amount);
    }


    function setCommission(uint8 _newRate) external onlyOwner {
        commission = _newRate;
    }
}

