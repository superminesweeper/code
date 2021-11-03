// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import './SafeMath.sol';
import "./SweepCoin.sol";
import "./SweepNFT.sol";
import "./SweepCoinEcologyPool.sol";

contract SweepCoinMiningPool {
    using SafeMath for uint256;

    address public _owner;
    SweepCoin private _Token;
    SweepNFT private _NFT;
    SweepCoinEcologyPool private _EcologyPool;
    address public ecologyPoolAddress;


    bool private isStart = false;
    //Final force
    uint256 private lpSupply = 0;

    // Number of coins produced per second
    uint256 public speed;
    //Update time of recording pledge or redemption
    uint256 public lastRewardTime;
    // Record the average number of outputs per second
    uint256 public accTokenPerShare;

    uint256 private _totalToken;
    mapping(address => uint256) private _ownerPow;
    mapping(address => uint256) private _ownerToken;

    struct MiningData {
        uint256 tokenId;
        uint256 coin;
        uint256 lp;
        uint256 rewardDebt;
        uint256 time;
        address owner;
    }


    //pledge record   tokenId =>  MiningData
    mapping(uint256 => MiningData)  private miningList;


    // all pledge tokens
    uint256[] private allPledgeTokendIds;
    // all token  position
    mapping(uint256 => uint256) private allTokenIdIndex;
    // address  -> [tokenId,tokenId]
    mapping(address => uint256[]) private ownedTokens;
    mapping(uint256 => uint256) private ownedTokenIndex;



    constructor (address coinAddress, address nftAddress)  {
        _owner = msg.sender;
        _Token = SweepCoin(coinAddress);
        _NFT = SweepNFT(nftAddress);
    }

    function startStatus() public view returns (bool) {
        return isStart;
    }


    function setStartStatus(bool isStart_) public {
        require(msg.sender == _owner, 'Only owner  have permissions');
        isStart = isStart_;
        if (isStart_ == false) {
            updateSpeed(0);
        }
    }

    function updateSpeed(uint256 speed_) public {
        require(msg.sender == _owner, 'Only owner  have permissions');
        require(speed_ >= 0, 'Illegal parameter');

        uint256 now_time = block.timestamp;
        if (lpSupply > 0 && lastRewardTime > 0) {
            uint256 total = now_time.sub(lastRewardTime).mul(speed).mul(1000);
            uint256 _accTokenPerShare = total.div(lpSupply);
            accTokenPerShare = accTokenPerShare.add(_accTokenPerShare);
            lastRewardTime = now_time;
        }

        speed = speed_;
    }


    function setEcologyPool(address ecologyPoolAddress_) public {
        ecologyPoolAddress = ecologyPoolAddress_;
        _EcologyPool = SweepCoinEcologyPool(ecologyPoolAddress_);
    }


    function pledgeInfo(uint256 tokenId_) public view returns (MiningData memory){
        return miningList[tokenId_];
    }

    function increasePledge(uint256 tokenId_, uint256 value) public {
        require(address(msg.sender) == address(tx.origin), "no contract");
        require(isStart == true, 'The ore pool is not opened');
        require(_Token.canUseBalanceOf(msg.sender) >= value, 'Insufficient account balance');
        SweepNFT.NFTData memory nft = _NFT.getTokenData(tokenId_);
        require(nft.tokenId == tokenId_, 'Illegal parameter');


        uint256 now_time = block.timestamp;


        //Increased computational power
        uint256 lp = 0;
        if (miningList[tokenId_].tokenId == 0) {
            require(msg.sender == _NFT.ownerOf(tokenId_), 'NFT does not belong to you');
            require(value == 0, 'Illegal parameter');

            _addPledgeTokend(tokenId_);

            lp = nft.coin.add(value);
            lp = lp.mul(nft.lucky).div(100).add(lp);

            miningList[tokenId_] = MiningData(tokenId_, value, lp, 0, now_time, msg.sender);
            _NFT.transferFrom(msg.sender, address(this), tokenId_);

        } else {
            MiningData storage mining = miningList[tokenId_];
            require(address(this) == _NFT.ownerOf(tokenId_), 'NFT does not belong to you');
            require(mining.owner == msg.sender, 'Illegal parameter');

            require(value > 0, 'Illegal parameter');

            mining.coin = mining.coin.add(value);
            uint256 nftLP = nft.coin.add(mining.coin);
            nftLP = nftLP.mul(nft.lucky).div(100).add(nftLP);
            lp = nftLP.sub(mining.lp);
            mining.lp = nftLP;
        }

        _ownerPow[msg.sender] = _ownerPow[msg.sender].add(lp);

        _totalToken = _totalToken.add(value);
        _ownerToken[msg.sender] = _ownerToken[msg.sender].add(value);


        if (lastRewardTime == 0) lastRewardTime = now_time;
        uint256 total = now_time.sub(lastRewardTime).mul(speed).mul(1000);
        uint256 _accTokenPerShare = 0;
        if (lpSupply == 0) {
            _accTokenPerShare = total.div(lp);
        } else {
            _accTokenPerShare = total.div(lpSupply);
        }

        accTokenPerShare = accTokenPerShare.add(_accTokenPerShare);
        uint256 rewardDebt = lp.mul(accTokenPerShare).div(1000);
        miningList[tokenId_].rewardDebt = miningList[tokenId_].rewardDebt.add(rewardDebt);

        lastRewardTime = now_time;
        lpSupply = lpSupply.add(lp);

        if (value > 0) {
            _Token.transferFrom(msg.sender, address(this), value);
        }

    }


    function reducePledge(uint256 tokenId_, uint256 value) public {
        require(address(msg.sender) == address(tx.origin), "no contract");
        MiningData storage mining = miningList[tokenId_];

        uint256 now_time = block.timestamp;

        require(msg.sender == mining.owner, 'NFT does not belong to you');
        require(address(this) == _NFT.ownerOf(mining.tokenId), 'NFT does not belong to contract');

        require(value > 0, 'Illegal data');

        require(mining.coin >= value, 'Insufficient pledge amount');

        _totalToken = _totalToken.sub(value);
        _ownerToken[msg.sender] = _ownerToken[msg.sender].sub(value);

        SweepNFT.NFTData memory nft = _NFT.getTokenData(tokenId_);


        // nft.coin + mining.coin + (nft.coin + mining.coin)*lucky

        mining.coin = mining.coin.sub(value);
        uint256 nftLP = nft.coin.add(mining.coin);
        nftLP = nftLP.mul(nft.lucky).div(100).add(nftLP);
        uint256 reduce_lp = mining.lp.sub(nftLP);

        _ownerPow[msg.sender] = _ownerPow[msg.sender].sub(reduce_lp);

        mining.lp = nftLP;

        uint256 total = now_time.sub(lastRewardTime).mul(speed).mul(1000);
        uint256 _accTokenPerShare = 0;
        if (lpSupply > 0) {
            _accTokenPerShare = total.div(lpSupply);
        }
        accTokenPerShare = accTokenPerShare.add(_accTokenPerShare);

        uint256 rewardDebt = reduce_lp.mul(accTokenPerShare).div(1000);
        mining.rewardDebt = mining.rewardDebt.sub(rewardDebt);

        lastRewardTime = now_time;
        lpSupply = lpSupply.sub(reduce_lp);
        //转移代币
        _Token.transfer(msg.sender, value);

    }


    function cancelPledge(uint256 tokenId_) public {
        require(address(msg.sender) == address(tx.origin), "no contract");
        MiningData storage mining = miningList[tokenId_];

        require(msg.sender == mining.owner, 'NFT does not belong to you');
        require(address(this) == _NFT.ownerOf(mining.tokenId), 'NFT does not belong to contract');

        _totalToken = _totalToken.sub(mining.coin);
        _ownerToken[msg.sender] = _ownerToken[msg.sender].sub(mining.coin);

        uint256 total = block.timestamp.sub(lastRewardTime).mul(speed).mul(1000);
        uint256 _accTokenPerShare = 0;
        if (lpSupply > 0) {
            _accTokenPerShare = total.div(lpSupply);
        }
        accTokenPerShare = accTokenPerShare.add(_accTokenPerShare);

        uint256 rewardDebt = mining.lp.mul(accTokenPerShare).div(1000);

        uint256 amount = mining.lp.mul(accTokenPerShare).div(1000).sub(rewardDebt);


        lastRewardTime = block.timestamp;
        lpSupply = lpSupply.sub(mining.lp);

        _ownerPow[msg.sender] = _ownerPow[msg.sender].sub(mining.lp);


        if (lpSupply == 0) {
            accTokenPerShare = 0;
            lastRewardTime = 0;
        }


        //转移代币
        _NFT.transferFrom(address(this), msg.sender, tokenId_);
        if (mining.coin.add(amount) > 0) {
            _Token.transfer(msg.sender, mining.coin.add(amount));
        }


        if (ecologyPoolAddress != address(0)) {
            _EcologyPool.awardMaster(msg.sender, mining.coin.add(amount));
        }

        delete miningList[tokenId_];
        _removePledgeTokend(tokenId_);
    }


    function canWithdrawalAmount(uint256 tokenId_) public view returns (uint256[2] memory) {

        MiningData memory mining = miningList[tokenId_];

        require(address(this) == _NFT.ownerOf(mining.tokenId), 'NFT does not belong to contract');

        uint256 now_time = block.timestamp;
        uint256 total = now_time.sub(lastRewardTime).mul(speed).mul(1000);
        uint256 _accTokenPerShare = 0;
        if (lpSupply > 0) {
            _accTokenPerShare = total.div(lpSupply);
        }
        _accTokenPerShare = accTokenPerShare.add(_accTokenPerShare);
        uint256 amount = mining.lp.mul(_accTokenPerShare).div(1000).sub(mining.rewardDebt);

        return [amount, now_time];

    }


    function withdrawal(uint256 tokenId_) public {
        require(address(msg.sender) == address(tx.origin), "no contract");
        uint256 amount = canWithdrawalAmount(tokenId_)[0];
        require(amount > 0, 'No withdrawable amount');

        MiningData storage mining = miningList[tokenId_];
        require(msg.sender == mining.owner, 'NFT does not belong to you');

        mining.rewardDebt = mining.rewardDebt.add(amount);
        _Token.transfer(msg.sender, amount);

        if (ecologyPoolAddress != address(0)) {
            _EcologyPool.awardMaster(msg.sender, amount);
        }

    }


    function nftPower(uint256 tokenId_) public view returns (uint256){
        return miningList[tokenId_].lp;
    }

    function totalPow() public view returns (uint256){
        return lpSupply;
    }


    function totalToken() public view returns (uint256){
        return _totalToken;
    }


    function ownerPower(address from) public view returns (uint256){
        return _ownerPow[from];
    }

    function ownerToken(address from) public view returns (uint256){
        return _ownerToken[from];
    }

    function blockTime() public view returns (uint256){
        return block.timestamp;
    }

    function totalPledge() public view returns (uint256) {
        return allPledgeTokendIds.length;
    }

    function pledgeTokenId(uint256 index_) public view returns (uint256) {
        require(index_ < allPledgeTokendIds.length, 'global index out of bounds');
        return allPledgeTokendIds[index_];
    }


    function ownerPledge(address from) public view returns (uint256) {
        return ownedTokens[from].length;
    }

    function ownerPledgeTokenId(address from, uint256 index_) public view returns (uint256) {
        require(index_ < ownedTokens[from].length, 'global index out of bounds');
        return ownedTokens[from][index_];
    }


    function _removePledgeTokend(uint256 tokenId_) private {

        uint256 cur_index = allTokenIdIndex[tokenId_];

        uint256 last_index = allPledgeTokendIds.length - 1;
        uint256 lastTokenId = allPledgeTokendIds[last_index];


        allPledgeTokendIds[cur_index] = lastTokenId;
        allTokenIdIndex[lastTokenId] = cur_index;


        delete allTokenIdIndex[tokenId_];
        allPledgeTokendIds.pop();


        uint256 owned_cur_index = ownedTokenIndex[tokenId_];

        uint256 owned_last_index = ownedTokens[msg.sender].length - 1;
        uint256 ownedlastTokenId = ownedTokens[msg.sender][owned_last_index];


        ownedTokens[msg.sender][owned_cur_index] = ownedlastTokenId;
        ownedTokenIndex[ownedlastTokenId] = owned_cur_index;

        delete ownedTokenIndex[tokenId_];
        ownedTokens[msg.sender].pop();

    }


    function _addPledgeTokend(uint256 tokenId_) private {
        allTokenIdIndex[tokenId_] = allPledgeTokendIds.length;
        allPledgeTokendIds.push(tokenId_);

        uint256 len = ownedTokens[msg.sender].length;
        ownedTokenIndex[tokenId_] = len;
        ownedTokens[msg.sender].push(tokenId_);

    }


}
