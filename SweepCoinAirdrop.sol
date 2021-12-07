// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "./Address.sol";
import './SafeMath.sol';
import "./SweepCoin.sol";
import "./SweepCoinEcologyPool.sol";


contract SweepCoinAirdrop {
    using SafeMath for uint256;
    using Address for address;

    address private _owner;
    SweepCoin private _Token;
    SweepCoinEcologyPool private _EcologyPool;
    address public ecologyPoolAddress;

    struct AirdropItem {
        address _address;
        uint256 _starttime;
        uint256 _endtime;
        uint256 _value;
        uint256 _day;
    }

    //Transfer of account airdrop balance is prohibited
    mapping(address => AirdropItem)  private _airdrop_balances;
    uint256 public airdropTotal;

    constructor (address tokenAddress)  {
        _owner = msg.sender;
        _Token = SweepCoin(tokenAddress);
    }


    function setEcologyPool(address ecologyPoolAddress_) public {
        ecologyPoolAddress = ecologyPoolAddress_;
        _EcologyPool = SweepCoinEcologyPool(ecologyPoolAddress_);
    }


    function airdropBalances(address to) public view returns (uint256) {
        if (_airdrop_balances[to]._address == address(0)) return 0;
        if (_airdrop_balances[to]._endtime <= block.timestamp) return 0;
        return _airdrop_balances[to]._value;
    }


    function airdropInfo(address to) public view returns (AirdropItem memory) {
        return _airdrop_balances[to];
    }


    function unlockAirdrop(address target) public {
        require(address(msg.sender) == address(tx.origin), "no contract");
        require(address(msg.sender) == _owner, "only owner  can transfer money ");
        require(address(msg.sender) != target, "You can't transfer money to yourself");
        require(_airdrop_balances[target]._address != address(0), "Lock record not found");
        require(_airdrop_balances[target]._endtime > block.timestamp, "Data unlocked, do not repeat");
        _airdrop_balances[target]._endtime = 0;
    }


    function sendAirdrop(address to, uint256 lockDay, uint256 value_, address master) public returns (uint256){

        require(address(msg.sender) == address(tx.origin), "no contract");
        require(address(msg.sender) == _owner, "only owner  can transfer money ");
        require(address(msg.sender) != to, "You can't transfer money to yourself");
        require(to != master, "Cannot bind from");
        require(!to.isContract(), "no contract !!");
        require(_owner != to, "Cannot transfer to administrator");
        require(_Token.isSetAirdopToken() == true, 'Token airdrop information not initialized');

        uint256 now_time = block.timestamp;

        uint256 value = value_.mul(10 ** uint256(_Token.decimals()));
        uint256 endtime = lockDay.mul(uint256(3600)).mul(uint256(24)).add(now_time);

        require(value > 0, "Amount must be greater than 0");
        require(_airdrop_balances[to]._address == address(0), "Airdrop record already exists");
        require(_Token.canUseBalanceOf(address(this)) >= value_, 'Insufficient contract address balance');

        _airdrop_balances[to] = AirdropItem(to, now_time, endtime, value, lockDay);
        _Token.transfer(to, value);


        if (master != address(0) && ecologyPoolAddress != address(0)) {
            _EcologyPool.bindApprentice(master, to);
        }

        airdropTotal = airdropTotal.add(value);

        return value;
    }


    function sendAirdropBatch(address[] memory tos, uint256 lockDay, uint256 value_, address[] memory masters) public returns (uint256){
        require(address(msg.sender) == _owner, "only owner can transfer money ");
        require(tos.length == masters.length, "only owner can transfer money ");
        uint256 value = value_.mul(10 ** uint256(_Token.decimals()));

        uint256 total_value = 0;

        for (uint8 i = 0; i < tos.length; i++) {
            total_value = total_value.add(value);
        }

        require(_Token.canUseBalanceOf(address(this)) >= total_value, 'Insufficient contract address balance');


        for (uint8 i = 0; i < tos.length; i++) {
            address to = tos[i];
            sendAirdrop(to, lockDay, value_, masters[i]);
        }

        return total_value;
    }


}
