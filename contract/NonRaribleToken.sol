// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract NonRaribleToken is ERC721,ERC721Enumerable,ERC721Royalty,ERC721URIStorage {
	
    using SafeERC20 for IERC20;

    //exten
    
    function _beforeTokenTransfer(
        address from,
        address to,
        uint tokenId
    ) internal virtual override(ERC721,ERC721Enumerable) {
		super._beforeTokenTransfer(from,to,tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721,ERC721Enumerable,ERC721Royalty)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _burn(uint tokenId) internal virtual override(ERC721,ERC721URIStorage,ERC721Royalty) {
        super._burn(tokenId);
    }

    
    function tokenURI(uint tokenId) public view virtual override(ERC721,ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    //var 

    uint constant priceChangeFreezeDuration=86400*7;

    bool immutable public buyWithETH;
    IERC20 immutable public buyToken;
    address immutable public creator;
    uint immutable public creatorShare;

	uint internal tokenIds=0;

    uint public price;
    uint public priceChangeUnfreezeTimestamp;

    //modifier

    modifier onlyTokenOwner(uint _tokenID) {
        require(ownerOf(_tokenID)==_msgSender(),"you not own this Token");
        _;
    }

    modifier onlyCreator() {
        require(_msgSender()==creator,"only Creator");
        _;
    }

    //contract owner

    constructor(
        string memory name_, string memory symbol_,

        bool _buyWithETH,
        address _buyToken,
        //uint _priceChangeFreezeDuration,

        address _creator,
        uint _creatorShare,
        uint _newPrice
    ) ERC721(name_, symbol_){

        //eth or token
        require((_buyWithETH && _buyToken==address(0)) || (!_buyWithETH && _buyToken!=address(0)),"ETH or token?");
        buyWithETH=_buyWithETH;
        buyToken=IERC20(_buyToken);

        //creator
        require(_creatorShare<=10000,"creator share over 100%");
        require(_creator != address(0), "invalid creator");
        creator=_creator;
        creatorShare=_creatorShare;

        price=_newPrice;
    }

    /*
    function setDefaultRoyalty( uint96 _creatorRoyalty) external onlyCreator {
        _setDefaultRoyalty(creator,_creatorRoyalty);
    }
    */

    function setPrice(
        uint _newPrice
    ) public onlyCreator {
        require(_newPrice>0,"price can not be 0");
        require(block.timestamp<priceChangeUnfreezeTimestamp,"price change freezed");
        price=_newPrice;
        priceChangeUnfreezeTimestamp=block.timestamp+priceChangeFreezeDuration;
    }

    //buyer

    function buy() public virtual payable returns (uint newTokenId){
        pay(price);
        newTokenId=mintNext();
    }

    function pay(uint _price) internal {
        if(buyWithETH){
            require(msg.value>=_price,"not enough");
            //payable(address(this)).transfer(msg.value);
        }else{
		    buyToken.transferFrom(_msgSender(), address(this), _price);
        }
    }

    function mintNext() internal returns (uint newTokenId){
        newTokenId=++tokenIds;
        _safeMint(_msgSender(),newTokenId);
    }
    
}
