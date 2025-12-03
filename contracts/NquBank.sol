// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract NquBank {
    string public bankName; // 銀行名字
    uint256 totalAmount;    // 銀行存款儲備
    address public admin;
    mapping(address=>uint256) balances; // 帳戶餘額

    constructor(string memory _name) {
        bankName = _name;
        admin    = msg.sender;
    }

    function getBalance() public view returns (uint256, uint256) {
        return (address(this).balance, totalAmount);
    }

    // 存款
    function deposit(uint256 _amount) public payable {
        require(_amount > 0, "amount must > 0");
        require(msg.value == _amount, "msg.value must equal amount");
        balances[msg.sender] += _amount;  // a += b; a = a + b;
        totalAmount += _amount;
        require(address(this).balance == totalAmount, "bank's balance must ok");
    }

    // 提款
    function withdraw(uint256 _amount) public payable {
        require(_amount > 0, "amount must > 0");
        require(balances[msg.sender] >= _amount, "user's balance not enough");
        balances[msg.sender] -= _amount;
        payable(msg.sender).transfer(_amount);
        totalAmount -= _amount;
        require(address(this).balance == totalAmount, "bank's balance must ok");
    }

    // 轉帳
    function transfer(address _to, uint256 _amount) public {
        require(_amount > 0, "amount must > 0");
        require(address(0) != _to, "to address must valid"); // 檢查帳戶地址不為 0
        require(balances[msg.sender] >= _amount, "user's balance not enough");
        balances[msg.sender] -= _amount;
        balances[_to] += _amount;
        require(address(this).balance == totalAmount, "bank's balance must ok");
    }

    function balanceOf(address _who) public view returns (uint256) {
        return balances[_who];
    }
}
