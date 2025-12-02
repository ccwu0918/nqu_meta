// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @title 簡易紅包合約
/// @notice 支援「平均分配」與「隨機金額」兩種紅包類型
contract redpacket {

    // 紅包類型：true 代表平均分配；false 代表隨機金額
    bool public rType;

    // 剩餘可被領取的紅包份數
    uint8 public rCount;

    // 紅包總金額（建立合約時設定，必須等於 msg.value）
    uint256 public rTotalAmount;

    // 發紅包的人（俗稱「土豪」），用來接收剩餘餘額與 selfdestruct 退款
    address payable public tuhao;

    // 紀錄每個地址是否已經領取過紅包，true 表示已領取過
    mapping(address => bool) isStake;

    /// @notice 建構子，在部署合約時設定紅包型態、份數與總金額，並同時把 ETH 存入合約
    /// @param _isAvg true 代表平均紅包；false 代表隨機紅包
    /// @param _count 紅包份數（可被領取的次數）
    /// @param _amount 紅包總金額（單位 wei，需等於部署時附帶的 msg.value）
    constructor(bool _isAvg, uint8 _count, uint256 _amount) payable {
        // 設定紅包型態（平均或隨機）
        rType = _isAvg;

        // 設定紅包總份數（同時也是當前剩餘可領取的份數）
        rCount = _count;

        // 設定紅包總金額
        rTotalAmount = _amount;

        // 紀錄發紅包的帳戶地址（部署合約的人），並轉型為 payable 以便之後轉帳或 selfdestruct
        tuhao = payable(msg.sender);

        // 檢查實際轉入合約的 ETH 是否與設定的總金額相同
        require(_amount == msg.value, "redpacket's balance is ok");
    }

    /// @notice 取得目前合約帳戶中的 ETH 餘額
    /// @return 回傳合約地址目前持有的 ETH（wei）
    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    /// @notice 領取紅包的函式
    /// @dev
    ///  - 每個地址僅能呼叫成功一次（透過 isStake 判斷）
    ///  - 若為平均紅包：以目前餘額 / 剩餘份數計算每份金額
    ///  - 若為隨機紅包：使用 keccak256 生成 0~9 的隨機數，按比例發放
    function stakePacket() public payable {
        // 要求仍有剩餘紅包份數，否則無法再領取
        require(rCount > 0, "red packet must left");

        // 要求合約中仍有餘額，避免除以零或轉帳失敗
        require(getBalance() > 0, "contratc's balance must enough");

        // 每個地址只能成功領取一次紅包
        require(!isStake[msg.sender], "user already stake");

        // 標記呼叫者已經領取過紅包
        isStake[msg.sender] = true;

        if (rType) {
            // 等值紅包模式（平均分配）
            // 使用目前合約餘額除以剩餘份數，確保每次都是按剩餘情況平均分配
            uint256 amount = getBalance() / rCount;

            // 將計算出的金額轉給呼叫者
            payable(msg.sender).transfer(amount);
        } else {
            // 隨機紅包模式

            // 若只剩最後一份紅包，則直接把合約中全部餘額都給當前呼叫者
            if (rCount == 1) {
                payable(msg.sender).transfer(getBalance());
            } else {
                // 透過 keccak256 將多個變數組合編碼產生一個較難預測的雜湊值
                // 參數包含：發紅包者地址、紅包總額、剩餘份數、當前區塊時間戳、領取者地址
                uint256 randnum = uint256(
                    keccak256(
                        abi.encode(
                            tuhao,
                            rTotalAmount,
                            rCount,
                            block.timestamp,
                            msg.sender
                        )
                    )
                ) % 10; // 取 0~9 之間的整數

                // 根據隨機數決定金額比例：餘額 * randnum / 10
                // 若 randnum 為 0，則本次可能領到 0（實務上通常會避免這種情況）
                uint256 amount = getBalance() * randnum / 10;

                // 轉帳給當前呼叫者
                payable(msg.sender).transfer(amount);
            }
        }

        // 每成功領取一次，就將剩餘紅包份數減一
        rCount--;
    }

    /// @notice 銷毀合約並把剩餘 ETH 轉回給發紅包者（tuhao）
    /// @dev 呼叫 selfdestruct 會移除合約並將合約餘額轉給指定地址
    /// @notice Withdraw remaining ETH to tuhao (only callable by tuhao)
    function withdrawRemaining() public {
        require(msg.sender == tuhao, "Only tuhao can withdraw");
        payable(tuhao).transfer(address(this).balance);
    }
}
