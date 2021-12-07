// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import './SafeMath.sol';
import "./SweepCoin.sol";
import "./SweepNFT.sol";


contract SweepCoinEcologyPool {
    using SafeMath for uint256;

    address  private _owner;
    SweepCoin private _Token;
    SweepNFT private _NFT;
    address public airdropAddress;

    address public miningAddress;


    // User level direct and indirect 1000% specific revenue
    struct LevelInfo {
        uint8 lv;
        uint256 direct_active_rate;
        uint256 indirect_active_rate;
        uint256 direct_extract_rate;
        uint256 indirect_extract_rate;
    }

    mapping(uint8 => LevelInfo)  private levelList;

    // apprentices => master
    mapping(address => address)  private masterRelationship;
    // Number of apprentices
    mapping(address => address[])  private apprentices;
    //Level of address
    mapping(address => LevelInfo)  private addressLvs;


    uint256 public totalWithdraw = 0;
    // aready Withdrawn rewards
    mapping(address => uint256)  private withdrawList;

    uint256 public totalUnWithdraw = 0;
    //Rewards to be withdrawn
    mapping(address => uint256)  private unwithdrawList;
    //NFT activation record
    mapping(uint256 => uint256)  private nftActiveList;


    constructor (address coinAddress, address nftAddress)  {
        _owner = msg.sender;
        _Token = SweepCoin(coinAddress);
        _NFT = SweepNFT(nftAddress);

        for (uint8 i = 1; i <= 5; i++) {
            levelList[i] = LevelInfo(i, 0, 0, 0, 0);
        }
    }

    function accidentWithdrawal(uint256 withdrawal_value) public {
        require(msg.sender == _owner, 'Only owner  have permissions');

        uint256 balance = _Token.canUseBalanceOf(address(this));
        balance = balance.sub(totalUnWithdraw);
        require(balance >= withdrawal_value, 'Insufficient balance of contract account');

        _Token.transfer(msg.sender, withdrawal_value);
    }

    // What needs to be done in the first step of releasing the contract
    function setAirdropAddress(address target) public {
        require(address(msg.sender) == _owner, "Insufficient permissions");
        airdropAddress = target;
    }


    function setMiningAddress(address target) public {
        require(address(msg.sender) == _owner, "Insufficient permissions");
        miningAddress = target;
    }


    function updateLevelInfo(uint8 lv_,
        uint256 direct_active_rate_, uint256 indirect_active_rate_,
        uint256 direct_extract_rate_, uint256 indirect_extract_rate_
    ) public {
        require(address(msg.sender) == _owner, "Insufficient permissions");
        require(levelList[lv_].lv > 0, "Illegal parameter");
        levelList[lv_] = LevelInfo(lv_, direct_active_rate_, indirect_active_rate_, direct_extract_rate_, indirect_extract_rate_);
    }


    function levelInfo(uint8 lv_) public view returns (LevelInfo memory){
        return levelList[lv_];
    }


    function setAddressLv(address target, uint8 lv_) public {
        require(address(msg.sender) == _owner, "Insufficient permissions");
        require(levelList[lv_].lv > 0, "Illegal parameter");
        addressLvs[target] = levelList[lv_];
    }


    function getAddressLv(address target) public view returns (LevelInfo memory) {
        LevelInfo memory info = addressLvs[target];

        if (info.lv == 0) return levelList[1];

        return info;
    }


    function getMaster(address target) public view returns (address) {
        return masterRelationship[target];
    }

    function apprenticeNum(address target) public view returns (uint256) {
        return apprentices[target].length;
    }


    function nftActiveTime(uint256 tokenId) public view returns (uint256) {
        return nftActiveList[tokenId];
    }


    function bindApprentice(address master, address apprentice) public {
        require(msg.sender == airdropAddress, 'No permission to call');
        require(master != apprentice, 'Cannot bind from');
        require(master != address(0));

        require(masterRelationship[apprentice] == address(0), 'Relationship already bound');

        if (masterRelationship[apprentice] == master) return;


        masterRelationship[apprentice] = master;
        apprentices[master].push(apprentice);
    }


    function apprenticeAddressByIndex(address master, uint256 index_) public view returns (address) {
        require(index_ < apprentices[master].length, 'global index out of bounds');
        return apprentices[master][index_];
    }


    // Award master
    function awardMaster(address target, uint256 amount) public {

        require(miningAddress == msg.sender, 'Contract is required to call');
        require(amount >= 0, 'Withdrawal amount must be greater than 0');

        if (amount == 0) return;

        uint256 balance = _Token.canUseBalanceOf(address(this));
        balance = balance.sub(totalUnWithdraw);
        if (balance <= 0) return;


        address directMaster = masterRelationship[target];

        if (directMaster != address(0)) {

            LevelInfo memory directInfo = getAddressLv(directMaster);

            uint256 directValue = directInfo.direct_extract_rate.mul(amount).div(1000);
            unwithdrawList[directMaster] = unwithdrawList[directMaster].add(directValue);

            totalUnWithdraw = totalUnWithdraw.add(directValue);

        }

        //inDirect reward Master reward
        if (masterRelationship[directMaster] != address(0)) {
            address inDirectMaster = masterRelationship[directMaster];
            LevelInfo memory indirectInfo = getAddressLv(inDirectMaster);

            uint256 indirectValue = indirectInfo.indirect_extract_rate.mul(amount).div(1000);
            unwithdrawList[inDirectMaster] = unwithdrawList[inDirectMaster].add(indirectValue);

            totalUnWithdraw = totalUnWithdraw.add(indirectValue);
        }

    }



    //Activate NFT rewards
    function activateNFT(uint256 tokenId) public {
        if (msg.sender != address(_NFT)) return;
        address tokenOwner = _NFT.ownerOf(tokenId);
        if (tokenOwner == address(0)) return;

        SweepNFT.NFTData memory nft = _NFT.getTokenData(tokenId);
        if (nft.tokenId != tokenId) return;

        if (nftActiveList[tokenId] > 0) return;


        if (masterRelationship[tokenOwner] == address(0)) return;

        nftActiveList[tokenId] = block.timestamp;

        uint256 nft_coin = nft.coin;
        // Direct reward Master reward
        address directMaster = masterRelationship[tokenOwner];


        if (directMaster != address(0)) {
            LevelInfo memory directInfo = getAddressLv(directMaster);

            uint256 directValue = directInfo.direct_active_rate.mul(nft_coin).div(1000);
            unwithdrawList[directMaster] = unwithdrawList[directMaster].add(directValue);

            totalUnWithdraw = totalUnWithdraw.add(directValue);
        }

        //inDirect reward Master reward
        if (masterRelationship[directMaster] != address(0)) {
            address inDirectMaster = masterRelationship[directMaster];
            LevelInfo memory indirectInfo = getAddressLv(inDirectMaster);

            uint256 indirectValue = indirectInfo.indirect_active_rate.mul(nft_coin).div(1000);
            unwithdrawList[inDirectMaster] = unwithdrawList[inDirectMaster].add(indirectValue);

            totalUnWithdraw = totalUnWithdraw.add(indirectValue);
        }

    }


    function withdrawCoin(address target) public view returns (uint256){
        return withdrawList[target];
    }


    function unWithdrawCoin(address target) public view returns (uint256){
        return unwithdrawList[target];
    }


    function withdraw() public {
        require(address(msg.sender) == address(tx.origin), "no contract");
        uint256 value = unwithdrawList[msg.sender];
        require(value > 0, 'Withdrawal amount must be greater than 0');

        uint256 balance = _Token.canUseBalanceOf(address(this));
        require(balance > 0, 'Insufficient balance of contract account');

        if (value > balance) {
            value = balance;
        }

        _Token.transfer(msg.sender, value);
        withdrawList[msg.sender] = withdrawList[msg.sender].add(value);
        unwithdrawList[msg.sender] = 0;
        totalWithdraw = totalWithdraw.add(value);
        totalUnWithdraw = totalUnWithdraw.sub(value);
    }

}
