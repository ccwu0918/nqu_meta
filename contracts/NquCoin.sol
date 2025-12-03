// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ----------------------------------------------------------------------------
// 1. IERC20 介面：告訴銀行合約，標準的代幣有哪些函式可以呼叫
// ----------------------------------------------------------------------------
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// ----------------------------------------------------------------------------
// 2. NQUCoin：一個簡易的 ERC-20 代幣，用於測試
//    (內建 mint 函式，讓任何人都可以給自己發幣測試)
// ----------------------------------------------------------------------------
contract NQUCoin is IERC20 {
    string public name = "NQU Coin";
    string public symbol = "NQU";
    uint8 public decimals = 18;
    uint256 public override totalSupply;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    constructor() {
        // 部署時預先鑄造 100 萬顆給部署者
        _mint(msg.sender, 1000000 * 10**18);
    }

    // 測試用：任何人都能呼叫此函式領取測試幣
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _mint(address to, uint256 amount) internal {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "ERC20: transfer amount exceeds balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        require(balanceOf[sender] >= amount, "ERC20: transfer amount exceeds balance");
        require(allowance[sender][msg.sender] >= amount, "ERC20: transfer amount exceeds allowance");
        
        allowance[sender][msg.sender] -= amount; // 扣除授權額度
        balanceOf[sender] -= amount;             // 扣除發送者餘額
        balanceOf[recipient] += amount;          // 增加接收者餘額
        
        emit Transfer(sender, recipient, amount);
        return true;
    }
}

// ----------------------------------------------------------------------------
// 3. TokenBank：只能存取特定 ERC-20 代幣的銀行
// ----------------------------------------------------------------------------
contract TokenBank {
    // 狀態變數
    IERC20 public token; // 記錄這家銀行接受哪種代幣
    mapping(address => uint256) public balances; // 使用者在銀行的餘額
    uint256 public totalDeposit; // 銀行總存款量

    // 事件：記錄資金流向
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    // 建構子：部署時需傳入 ERC-20 代幣合約的地址
    constructor(address _tokenAddress) {
        require(_tokenAddress != address(0), "Invalid token address");
        token = IERC20(_tokenAddress);
    }

    // ------------------------------------------------------------------------
    // 存款函式
    // 注意：這裡不需要 `payable`，因為我們不是收 ETH
    // 前提：使用者必須先在代幣合約執行 `approve(BankAddress, amount)`
    // ------------------------------------------------------------------------
    function deposit(uint256 _amount) external {
        require(_amount > 0, "Amount must be > 0");

        // 1. 下載到本地變數 (Checks)
        uint256 balanceBefore = token.balanceOf(address(this));

        // 2. 呼叫代幣合約將幣轉入銀行 (Interactions)
        // 使用 transferFrom：從 msg.sender 轉到 address(this)
        bool success = token.transferFrom(msg.sender, address(this), _amount);
        require(success, "Token transfer failed");

        // 3. 安全檢查：確認實際收到的代幣數量 (防範通縮型代幣 Fee-on-transfer)
        uint256 balanceAfter = token.balanceOf(address(this));
        uint256 actualAmount = balanceAfter - balanceBefore;

        // 4. 更新內部帳本 (Effects)
        balances[msg.sender] += actualAmount;
        totalDeposit += actualAmount;

        emit Deposit(msg.sender, actualAmount);
    }

    // ------------------------------------------------------------------------
    // 提款函式
    // ------------------------------------------------------------------------
    function withdraw(uint256 _amount) external {
        // 1. 檢查餘額 (Checks)
        require(_amount > 0, "Amount must be > 0");
        require(balances[msg.sender] >= _amount, "Insufficient balance");

        // 2. 更新內部帳本 (Effects)
        // 先扣款，再轉帳，這是防範重入攻擊 (Reentrancy) 的黃金法則
        balances[msg.sender] -= _amount;
        totalDeposit -= _amount;

        // 3. 將代幣轉回給使用者 (Interactions)
        // 銀行是代幣持有者，直接用 transfer 轉給使用者
        bool success = token.transfer(msg.sender, _amount);
        require(success, "Token transfer failed");

        emit Withdraw(msg.sender, _amount);
    }

    // 查詢使用者餘額
    function getBalance(address _user) external view returns (uint256) {
        return balances[_user];
    }
}