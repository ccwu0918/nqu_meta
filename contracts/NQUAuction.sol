// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract NquAuction {
    address payable owner; // 管理員
    address payable seller; // 賣方
    uint256 public highestBid; // 最高出價金額
    address payable public highestBider; // 最高出價者
    uint256 public startBid; // 起標價
    uint256 public endTime; // 結束時間
    bool public isFinshed; // 是否已經結束
    
    // 事件定義
    event BidEvent(address _higher, uint256 highAmount); // 出價事件
    event EndBidEvent(address _winner, uint256 _amount); // 結束競標事件

    // 建構子：新增 _durationMinutes 參數以設定拍賣長度
    constructor(address _seller, uint256 _startBid, uint256 _durationMinutes) {
        owner = payable(msg.sender);
        seller = payable(_seller);
        startBid = _startBid;
        isFinshed = false;
        
        // 設定結束時間 = 當前區塊時間 + (輸入的分鐘數 * 60秒)
        // 這樣就能根據部署時的設定來決定拍賣長短
        endTime = block.timestamp + (_durationMinutes * 1 minutes);
        
        highestBid = 0;
    }

    function bid(uint256 _amount) public payable {
        require(_amount > highestBid, "amount must > highestBid");
        require(_amount == msg.value, "amount must equal value");
        require(!isFinshed, "auction already finished");
        require(block.timestamp < endTime, "auction already time out");

        // 將前一位最高出價者的保證金退回
        if (address(0) != highestBider) {
            highestBider.transfer(highestBid);
        }
        highestBid = _amount; // 更新目前最高出價金額
        highestBider = payable(msg.sender); // 更新目前最高出價者

        emit BidEvent(msg.sender, _amount); // 觸發出價事件
    }

    function endAuction() public payable {
        require(!isFinshed, "auction already finished");
        require(msg.sender == owner, "only owner can end auction");
        isFinshed = true; // 將競標狀態設為已結束
        seller.transfer(highestBid * 90 / 100); // 將成交金額的 90% 支付給賣方
        owner.transfer(highestBid * 10 / 100);  // 管理員收取 10% 服務費

        emit EndBidEvent(highestBider, highestBid); // 觸發競標結束事件
    }
    
    // 為了讓 DApp 能夠讀取 private 變數 (如果上面的變數沒加 public)，
    // 或是為了確保變數名稱對應，這裡補充讀取函數 (雖然上面變數已設為 public，這些可選)
    function getOwner() public view returns (address) {
        return owner;
    }
}