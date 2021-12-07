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


    bool public isStart = false;
    //Final force
    uint256 public lpSupply = 0;

    // Number of coins produced per second
    uint256 public speed;
    //Update time of recording pledge or redemption
    uint256 public lastRewardTime;
    // Record the average number of outputs per second
    uint256 public accTokenPerShare;

    uint256 public _totalToken;
    mapping(address => uint256) public _ownerPow;
    mapping(address => uint256) public _ownerToken;

    struct MiningData {
        uint256 tokenId;
        uint256 coin;
        uint256 lp;
        uint256 rewardDebt;
        uint256 time;
        address owner;
        bool is_positive;
    }

    uint256 public magnification = 1000000000000000000;

    //pledge record   tokenId =>  MiningData
    mapping(uint256 => MiningData)  private miningList;


    // all pledge tokens
    uint256[] private allPledgeTokendIds;
    // all token  position
    mapping(uint256 => uint256) private allTokenIdIndex;
    // address  -> [tokenId,tokenId]
    mapping(address => uint256[]) private ownedTokens;
    mapping(uint256 => uint256) private ownedTokenIndex;


    uint256 public withdrawal_lock_hours = 4320;
    uint256 public withdrawal_interval_hours = 24;


    struct LockInfo {
        uint256 start_time;
        uint256 end_time;
        uint256 value;
        uint256 lock_hours;
        uint256 cur_index;
        uint256 prev_index;
        uint256 next_index;
    }

    struct AddressLockInfo {
        uint256 num;
        uint256 value;
        uint256 first_index;
        uint256 last_index;
        uint256 withdrawal_time;
    }

    mapping(address => LockInfo[]) public lockProfitList;
    mapping(address => AddressLockInfo) public addressLock;




    constructor (address coinAddress, address nftAddress)  {
        _owner = msg.sender;
        _Token = SweepCoin(coinAddress);
        _NFT = SweepNFT(nftAddress);
    }

    function startStatus() public view returns (bool) {
        return isStart;
    }

    function accidentWithdrawal(uint256 withdrawal_value) public {
        require(msg.sender == _owner, 'Only owner  have permissions');

        uint256 balance = _Token.canUseBalanceOf(address(this));
        balance = balance.sub(_totalToken);
        require(balance >= withdrawal_value, 'Insufficient balance of contract account');

        _Token.transfer(msg.sender, withdrawal_value);
    }


    function setStartStatus(bool isStart_) public {
        require(msg.sender == _owner, 'Only owner  have permissions');

        if (isStart_ == true) {
            uint256 balance = _Token.canUseBalanceOf(address(this));
            balance = balance.sub(_totalToken);
            require(balance > 0, 'Insufficient balance of contract account');
        }

        if (isStart_ == false) {
            updateSpeed(0);
        }
        isStart = isStart_;

    }

    function updateSpeed(uint256 speed_) public {
        require(msg.sender == _owner, 'Only owner  have permissions');
        require(speed_ >= 0, 'Illegal parameter');
        require(isStart == true, 'Pool is not opened');

        uint256 now_time = block.timestamp;
        if (lpSupply > 0 && lastRewardTime > 0) {
            uint256 total = now_time.sub(lastRewardTime).mul(speed).mul(magnification);
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
        require(isStart == true, 'The  pool is not opened');
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

            miningList[tokenId_] = MiningData(tokenId_, value, lp, 0, now_time, msg.sender, true);
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
        uint256 total = now_time.sub(lastRewardTime).mul(speed).mul(magnification);
        uint256 cur_accTokenPerShare = 0;
        if (lpSupply != 0) {
            cur_accTokenPerShare = total.div(lpSupply).add(accTokenPerShare);
        }

        accTokenPerShare = cur_accTokenPerShare;
        uint256 rewardDebt = lp.mul(accTokenPerShare).div(magnification);

        if (miningList[tokenId_].is_positive) {
            // default func
            miningList[tokenId_].rewardDebt = miningList[tokenId_].rewardDebt.add(rewardDebt);
        } else {
            if (miningList[tokenId_].rewardDebt > rewardDebt) {
                miningList[tokenId_].rewardDebt = miningList[tokenId_].rewardDebt.sub(rewardDebt);
            } else {
                miningList[tokenId_].rewardDebt = rewardDebt.sub(miningList[tokenId_].rewardDebt);
                miningList[tokenId_].is_positive = true;
            }
        }

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

        uint256 total = now_time.sub(lastRewardTime).mul(speed).mul(magnification);
        uint256 cur_accTokenPerShare = 0;
        if (lpSupply > 0) {
            cur_accTokenPerShare = total.div(lpSupply).add(accTokenPerShare);
        }
        accTokenPerShare = cur_accTokenPerShare;

        uint256 rewardDebt = reduce_lp.mul(accTokenPerShare).div(magnification);

        if (mining.is_positive) {
            if (mining.rewardDebt > rewardDebt) {
                mining.rewardDebt = mining.rewardDebt.sub(rewardDebt);
            } else {
                mining.rewardDebt = rewardDebt.sub(mining.rewardDebt);
                mining.is_positive = false;
            }
        } else {
            mining.rewardDebt = mining.rewardDebt.add(rewardDebt);
        }

        lastRewardTime = now_time;
        lpSupply = lpSupply.sub(reduce_lp);
        _Token.transfer(msg.sender, value);

    }

    function cancelPledge(uint256 tokenId_) public {
        require(address(msg.sender) == address(tx.origin), "no contract");

        MiningData storage mining = miningList[tokenId_];

        require(msg.sender == mining.owner, 'NFT does not belong to you');
        require(address(this) == _NFT.ownerOf(mining.tokenId), 'NFT does not belong to contract');

        _totalToken = _totalToken.sub(mining.coin);
        _ownerToken[msg.sender] = _ownerToken[msg.sender].sub(mining.coin);


        uint256[2] memory amountInfo = canWithdrawalAmount(tokenId_);
        uint256 now_time = amountInfo[1];
        uint256 amount = amountInfo[0];

        require((now_time - addressLock[msg.sender].withdrawal_time) >= withdrawal_interval_hours.mul(3600), 'Withdrawal interval cooling');


        lastRewardTime = now_time;
        lpSupply = lpSupply.sub(mining.lp);
        _ownerPow[msg.sender] = _ownerPow[msg.sender].sub(mining.lp);


        if (lpSupply == 0) {
            accTokenPerShare = 0;
            lastRewardTime = 0;
        }

        _NFT.transferFrom(address(this), msg.sender, tokenId_);

        if (ecologyPoolAddress != address(0) && amount > 0) {
            _EcologyPool.awardMaster(msg.sender, amount);
        }


        uint256 balance = _Token.canUseBalanceOf(address(this));
        balance = balance.sub(_totalToken);


        if (mining.coin.add(amount) > 0 && mining.coin.add(amount) < balance) {
            if (withdrawal_lock_hours == 0) {
                _Token.transfer(msg.sender, mining.coin.add(amount));
            } else {
                if (mining.coin > 0) _Token.transfer(msg.sender, mining.coin);
                _lockProfit(msg.sender, amount);
            }
        }

        delete miningList[tokenId_];
        _removePledgeTokend(tokenId_);
    }

    function canWithdrawalAmount(uint256 tokenId_) public view returns (uint256[2] memory) {

        MiningData memory mining = miningList[tokenId_];

        require(address(this) == _NFT.ownerOf(mining.tokenId), 'NFT does not belong to contract');


        uint256 now_time = block.timestamp;
        uint256 total = now_time.sub(lastRewardTime).mul(speed).mul(magnification);
        uint256 cur_accTokenPerShare = 0;
        if (lpSupply > 0) {
            cur_accTokenPerShare = total.div(lpSupply).add(accTokenPerShare);
        }

        uint256 amount = 0;

        if (mining.is_positive) {
            //default
            amount = mining.lp.mul(cur_accTokenPerShare).div(magnification).sub(mining.rewardDebt);
        } else {
            amount = mining.lp.mul(cur_accTokenPerShare).div(magnification).add(mining.rewardDebt);
        }

        return [amount, now_time];

    }

    function withdrawal(uint256 tokenId_) public {
        require(address(msg.sender) == address(tx.origin), "no contract");

        uint256[2] memory amountInfo = canWithdrawalAmount(tokenId_);
        uint256 now_time = amountInfo[1];
        uint256 amount = amountInfo[0];
        require(amount > 0, 'No withdrawable amount');

        require((now_time - addressLock[msg.sender].withdrawal_time) >= withdrawal_interval_hours.mul(3600), 'Withdrawal interval cooling');


        uint256 balance = _Token.canUseBalanceOf(address(this));
        balance = balance.sub(_totalToken);
        require(balance > 0, 'Insufficient balance of contract account');

        if (amount > balance) {
            amount = balance;
            setStartStatus(false);
        }

        MiningData storage mining = miningList[tokenId_];
        require(msg.sender == mining.owner, 'NFT does not belong to you');


        if (mining.is_positive) {
            mining.rewardDebt = mining.rewardDebt.add(amount);
        } else {
            if (mining.rewardDebt > amount) {
                mining.rewardDebt = mining.rewardDebt.sub(amount);
            } else {
                mining.rewardDebt = amount.sub(mining.rewardDebt);
                mining.is_positive = true;
            }
        }


        if (withdrawal_lock_hours == 0) {
            _Token.transfer(msg.sender, amount);
        } else {
            _lockProfit(msg.sender, amount);
        }

        if (ecologyPoolAddress != address(0)) {
            _EcologyPool.awardMaster(msg.sender, amount);
        }

    }

    function _lockProfit(address target, uint256 value_) internal {

        uint256 start_time = block.timestamp;
        uint256 lock_time = withdrawal_lock_hours.mul(3600);
        uint256 end_time = start_time.add(lock_time);


        uint256 last_index = addressLock[target].last_index;


        if (lockProfitList[target].length > 0) {
            lockProfitList[target][last_index].next_index = lockProfitList[target].length;
        }

        uint256 cur_index = lockProfitList[target].length;
        uint256 prev_index = last_index;
        uint256 next_index = cur_index;

        lockProfitList[target].push(LockInfo(start_time, end_time, value_, withdrawal_lock_hours, cur_index, prev_index, next_index));

        addressLock[target].num = addressLock[target].num.add(1);
        addressLock[target].value = addressLock[target].value.add(value_);
        addressLock[target].last_index = lockProfitList[target].length - 1;
        addressLock[target].withdrawal_time = start_time;


    }

    function _unLockRecord(uint256 index_) internal returns (uint256){

        uint256 now_time = block.timestamp;
        require(index_ < lockProfitList[msg.sender].length, 'Array length out of bounds');
        require(lockProfitList[msg.sender][index_].end_time < now_time, 'The data is not unlocked');

        uint256 res_value = lockProfitList[msg.sender][index_].value;

        // Only one piece of data
        if (lockProfitList[msg.sender].length == 1) {
            addressLock[msg.sender].num = 0;
            addressLock[msg.sender].value = 0;
            addressLock[msg.sender].first_index = 0;
            addressLock[msg.sender].last_index = 0;
            addressLock[msg.sender].withdrawal_time = now_time;
            delete lockProfitList[msg.sender];
            return res_value;
        }

        // delete of position index 2
        uint256 del_per_index = lockProfitList[msg.sender][index_].prev_index;
        // 1
        uint256 del_next_index = lockProfitList[msg.sender][index_].next_index;
        // 2

        if (del_per_index != index_) {
            if (del_next_index != index_) {
                lockProfitList[msg.sender][del_per_index].next_index = del_next_index;
            } else {
                // index is last
                if (lockProfitList[msg.sender].length == 2) {
                    lockProfitList[msg.sender][del_per_index].next_index = 0;
                    lockProfitList[msg.sender][del_per_index].prev_index = 0;
                    addressLock[msg.sender].first_index = 0;
                } else {
                    lockProfitList[msg.sender][del_per_index].next_index = del_per_index;
                }
            }
        } else {
            addressLock[msg.sender].first_index = del_next_index;
            lockProfitList[msg.sender][del_next_index].prev_index = del_next_index;
        }


        if (del_next_index != index_) {
            if (del_per_index != index_) {
                lockProfitList[msg.sender][del_next_index].prev_index = del_per_index;
            } else {
                lockProfitList[msg.sender][del_next_index].prev_index = del_next_index;
                addressLock[msg.sender].first_index = del_next_index;
            }
        } else {
            addressLock[msg.sender].last_index = del_per_index;
            lockProfitList[msg.sender][del_per_index].next_index = del_per_index;
        }


        // change of position
        uint256 len = lockProfitList[msg.sender].length - 1;


        uint256 change_per_index = lockProfitList[msg.sender][len].prev_index;
        uint256 change_next_index = lockProfitList[msg.sender][len].next_index;

        if (index_ != len) {
            if (change_per_index != len) {
                lockProfitList[msg.sender][change_per_index].next_index = index_;
            } else {
                addressLock[msg.sender].first_index = index_;
                lockProfitList[msg.sender][len].prev_index = index_;
            }

            if (change_next_index != len) {
                lockProfitList[msg.sender][change_next_index].prev_index = index_;
            } else {
                lockProfitList[msg.sender][change_per_index].next_index = index_;
                addressLock[msg.sender].last_index = index_;
                lockProfitList[msg.sender][len].next_index = index_;
            }

        } else {

            if (change_per_index != len) {
                if (change_next_index != len) {
                    lockProfitList[msg.sender][change_per_index].next_index = change_next_index;
                    lockProfitList[msg.sender][change_next_index].prev_index = change_per_index;
                } else {
                    addressLock[msg.sender].last_index = change_per_index;
                    lockProfitList[msg.sender][change_per_index].next_index = change_per_index;
                }

            } else {
                addressLock[msg.sender].first_index = change_next_index;
                lockProfitList[msg.sender][change_next_index].prev_index = change_next_index;
            }
        }


        lockProfitList[msg.sender][index_] = lockProfitList[msg.sender][len];
        lockProfitList[msg.sender][index_].cur_index = index_;


        addressLock[msg.sender].num = addressLock[msg.sender].num.sub(1);
        addressLock[msg.sender].value = addressLock[msg.sender].value.sub(res_value);

        lockProfitList[msg.sender].pop();

        return res_value;
    }

    function unLockProfit(uint256 [] memory unlock_indexs) public {

        uint256 unlock_value = 0;
        require(unlock_indexs.length > 0 && unlock_indexs.length <= 30, 'Too much operation data');


        bool is_legal = true;

        for (uint8 i = 0; i < unlock_indexs.length; i++) {
            if (i >= (unlock_indexs.length - 1)) {
                unlock_value = unlock_value.add(_unLockRecord(unlock_indexs[unlock_indexs.length - 1]));
                continue;
            }

            if (unlock_indexs[i] < unlock_indexs[i + 1]) {
                is_legal = false;
                break;
            }

            if (unlock_indexs[i] < 0 || unlock_indexs[i] >= addressLock[msg.sender].num) {
                is_legal = false;
                break;
            }
            unlock_value = unlock_value.add(_unLockRecord(unlock_indexs[i]));
        }

        require(is_legal == true, 'Illegal unlock parameter');

        require(unlock_value > 0, 'Insufficient unlocking amount');

        _Token.transfer(msg.sender, unlock_value);

    }

    function updateWithdrawalIntervalHours(uint256 interval_hours) public {
        require(msg.sender == _owner, 'Only owner  have permissions');
        require(interval_hours >= 0, 'The interval must be greater than or equal to 0');
        withdrawal_interval_hours = interval_hours;
    }

    function updateWithdrawalLockHours(uint256 lock_hours) public {
        require(msg.sender == _owner, 'Only owner  have permissions');
        require(lock_hours >= 0, 'The interval must be greater than or equal to 0');
        withdrawal_lock_hours = lock_hours;
    }

    function nftPower(uint256 tokenId_) public view returns (uint256){
        return miningList[tokenId_].lp;
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
