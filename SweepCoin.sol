// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import './SafeMath.sol';
import './SweepCoinAirdrop.sol';

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address who) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function approve(address spender, uint256 value) external returns (bool);

    function transferFrom(address from, address to, uint256 value) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract SweepCoin is IERC20 {
    using SafeMath for uint256;

    uint256   private _decimals;
    string  private _name;
    string  private _symbol;
    uint256 internal _totalSupply;

    address private _owner;
    uint256 public _burnValue;
    mapping(address => uint256) public _burnValueMap;

    SweepCoinAirdrop private Airdrop;
    bool private is_airdrop_init = false;


    constructor (uint256 totalSupply_, string memory name_, uint256 decimals_, string memory symbol_)  {
        _decimals = decimals_;
        _totalSupply = totalSupply_.mul(10 ** uint256(_decimals));
        _balances[msg.sender] = totalSupply_.mul(10 ** uint256(_decimals));
        _name = name_;
        _symbol = symbol_;
        _owner = msg.sender;
    }

    /**
    * @return the name of the token.
    */
    function name() public view returns (string memory) {
        return _name;
    }

    /**
    * @return the symbol of the token.
    */
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /**
  * @return the number of decimals of the token.
  */
    function decimals() public view returns (uint256) {
        return _decimals;
    }


    mapping(address => uint256) internal _balances;

    mapping(address => mapping(address => uint256)) private _allowed;


    function balanceOf(address target_address) override public view returns (uint256) {
        return _balances[target_address];
    }

    function canUseBalanceOf(address target_address)  public view returns (uint256) {
        return _balances[target_address].sub(airdropBalanceOf(target_address));
    }

    function airdropBalanceOf(address target_address) public view returns (uint256) {
        uint256 airdrop_balance = 0;
        if (is_airdrop_init) airdrop_balance = Airdrop.airdropBalances(target_address);
        return airdrop_balance;
    }


    /**
    * @dev Total number of tokens in existence
    */
    function totalSupply() override public view returns (uint256) {
        return _totalSupply;
    }

    function allowance(address owner, address spender) override public view returns (uint256) {
        return _allowed[owner][spender];
    }

    function transfer(address to, uint256 value) override public returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function burnToZero(address from, uint256 value) public returns (bool) {

        require(value > 0, "amount must be greater than 0");

        require(value <= _allowed[from][msg.sender]);
        _allowed[from][msg.sender] = _allowed[from][msg.sender].sub(value);

        address to = address(0);
        _burnValue = _burnValue.add(value);
        _burnValueMap[from] = _burnValueMap[from] .add(value);

        uint256 airdrop_balance = airdropBalanceOf(from);
        require(value <= (_balances[from].sub(airdrop_balance)), 'Insufficient account balance');
        _balances[from] = _balances[from].sub(value);
        _balances[to] = _balances[to].add(value);

        emit Transfer(from, to, value);
        return true;
    }


    function approve(address spender, uint256 value) override public returns (bool) {
        require(value > 0, "amount must be greater than 0");
        require(spender != address(0));
        _allowed[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) override public returns (bool) {
        require(value > 0, "amount must be greater than 0");
        require(value <= _allowed[from][msg.sender]);
        _allowed[from][msg.sender] = _allowed[from][msg.sender].sub(value);
        _transfer(from, to, value);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        require(addedValue > 0, "amount must be greater than 0");
        require(spender != address(0));
        _allowed[msg.sender][spender] = (_allowed[msg.sender][spender].add(addedValue));
        emit Approval(msg.sender, spender, _allowed[msg.sender][spender]);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        require(subtractedValue > 0, "amount must be greater than 0");
        require(spender != address(0));
        _allowed[msg.sender][spender] = (_allowed[msg.sender][spender].sub(subtractedValue));
        emit Approval(msg.sender, spender, _allowed[msg.sender][spender]);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(value > 0, "amount must be greater than 0");
        require(to != address(0));
        uint256 airdrop_balance = airdropBalanceOf(from);
        require(value <= (_balances[from].sub(airdrop_balance)), 'Insufficient account balance');
        _balances[from] = _balances[from].sub(value);
        _balances[to] = _balances[to].add(value);
        emit Transfer(from, to, value);
    }


    function setAirdopToken(address airdrop_address) public {
        require(address(msg.sender) == _owner, "Insufficient permissions");
        Airdrop = SweepCoinAirdrop(airdrop_address);
        is_airdrop_init = true;
    }

    function isSetAirdopToken() public view returns (bool) {
        return is_airdrop_init;
    }


}


