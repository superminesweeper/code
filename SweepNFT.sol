// SPDX-License-Identifier: MIT

pragma solidity ^0.8.1;


import "./Ownable.sol";
import "./ERC721Enumerable.sol";
import "./SweepCoin.sol";
import './SafeMath.sol';
import './SweepCoinEcologyPool.sol';
import './SweepCoinMiningPool.sol';

contract SweepNFT is ERC721Enumerable, Ownable {

    using SafeMath for uint256;
    using Strings for uint256;

    SweepCoin private _Token;

    SweepCoinEcologyPool private _EcologyPool;
    address public ecologyPoolAddress;


    struct NFTData {
        uint256 tokenId;
        uint256 time;
        uint256 coin;
        uint256 fee;
        uint256 width;
        uint256 height;
        uint256[] points;  //  [0,20,44,108,200,310]
        uint256 lucky; //Lucky value 0~5%
    }



    // Optional mapping for token URIs
    mapping(uint256 => string) private _tokenURIs;

    // Base URI
    string private _baseURIextended;

    // Minimum width
    uint256 private min_wh = 9;
    uint256 private max_wh = 30;

    //  Proportion of Mines
    uint256 private min_mine = 10;  // Proportion of Mines 10%
    uint256 private max_mine = 30;   //  Proportion of Mines 30%

    mapping(uint256 => NFTData) private _tokenData;   // utokenId => NFTData
    mapping(string => uint256) private _tokenUnique;  //   width/height/0/20/44/108/200   unique string => tokenId



    constructor(string memory _name, string memory _symbol, address _coin_address)
    ERC721(_name, _symbol)
    {
        _Token = SweepCoin(_coin_address);
    }


    function setCoinEcologyPool(address pool_address) external onlyOwner() {
        _EcologyPool = SweepCoinEcologyPool(pool_address);
        ecologyPoolAddress = pool_address;
    }


    function setWH(uint256 min_wh_, uint256 max_wh_) external onlyOwner() {
        min_wh = min_wh_;
        max_wh = max_wh_;
    }

    function getWH() public view returns (uint256[2] memory) {
        return [min_wh, max_wh];
    }


    function setMineRatio(uint256 min_mine_, uint256 max_mine_) external onlyOwner() {
        min_mine = min_mine_;
        max_mine = max_mine_;
    }

    function getMineRatio() public view returns (uint256[2] memory) {
        return [min_mine, max_mine];
    }

    function setBaseURI(string memory baseURI_) external onlyOwner() {
        _baseURIextended = baseURI_;
    }

    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal virtual {
        require(_exists(tokenId), "ERC721Metadata: URI set of nonexistent token");
        _tokenURIs[tokenId] = _tokenURI;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseURIextended;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        string memory _tokenURI = _tokenURIs[tokenId];
        string memory base = _baseURI();

        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_tokenURI).length > 0) {
            return string(abi.encodePacked(base, _tokenURI));
        }
        // If there is a baseURI but no tokenURI, concatenate the tokenID to the baseURI.
        return string(abi.encodePacked(base, tokenId.toString()));
    }


    function createNft(uint256 tokenId_, uint256 width_, uint256 height_, uint256[] memory points_,

        address idea_address, uint256 fee_) public {


        require(address(msg.sender) == address(tx.origin), "no contract");

        require(fee_ >= 0, 'Illegal creation fee');
        require(width_ >= min_wh, 'Illegal width');
        require(width_ <= max_wh, 'Illegal : width');

        require(height_ >= min_wh, 'Illegal height');
        require(height_ <= max_wh, 'Illegal : height');

        uint256 w_h = width_.mul(height_);
        uint256 coin = w_h.mul(10 ** uint256(_Token.decimals()));

        fee_ = fee_.mul(10 ** uint256(_Token.decimals()));


        uint256 total_cost = coin;
        if (fee_ > 0 && msg.sender != idea_address) {
            total_cost = total_cost.add(fee_);
        }

        require(_Token.canUseBalanceOf(msg.sender) >= total_cost, 'Insufficient account available balance');


        //Whether the calculation point is legal
        require(points_.length >= w_h.mul(min_mine).div(100), 'Illegal points count');
        require(points_.length <= w_h.mul(max_mine).div(100), 'Illegal points count');
        bool is_legal = true;
        for (uint8 i = 0; i < points_.length; i++) {
            if (points_[i] >= w_h || points_[i] < 0) {
                is_legal = false;
                break;
            }
        }

        require(is_legal, 'Illegal points');


        string memory unique_str = string(abi.encodePacked(width_.toString(), '/', height_.toString(), '/'));

        for (uint8 i = 0; i < points_.length; i++) {
            unique_str = string(abi.encodePacked(unique_str, '/', points_[i].toString()));
        }

        require(_tokenUnique[unique_str] == 0, 'Duplicate existence');
        _tokenUnique[unique_str] = tokenId_;


        _mint(msg.sender, tokenId_);

        uint256 lucky = rand(tokenId_) % 10;
        if (lucky == 0) lucky = 0;
        if (lucky > 5) lucky = 0;
        _tokenData[tokenId_] = NFTData(tokenId_, block.timestamp, coin, fee_, width_, height_, points_, lucky);


        // Buy someone else's NFT
        if (fee_ > 0 && msg.sender != idea_address) {
            _Token.transferFrom(msg.sender, idea_address, fee_);
        }
        //Activate and  destroy token
        _Token.burnToZero(msg.sender, coin);

        // "233","9","9",[0,"4",8,"36",40,"44",72,"76",80],"0x2d658C3F95Aef74303d5a630C6373566C60516E0","23"

        if (ecologyPoolAddress != address(0)) {
            //Payment of commission
            _EcologyPool.activateNFT(tokenId_);
        }
    }


    function getTokenData(uint256 tokenId) public view returns (NFTData memory){
        return _tokenData[tokenId];
    }

    function rand(uint256 len) internal view returns (uint256) {
        uint256 random = uint256(keccak256(abi.encodePacked(block.difficulty, block.timestamp)));
        return random % (uint256(4123456).add(len));
    }

}
