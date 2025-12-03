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
        // 部署時預先鑄造 1000 萬顆給部署者
        _mint(msg.sender, 10000000 * 10**18);
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
contract TokenBankV5 {
    // --- 狀態變數 ---
    IERC20 public immutable authorizedToken;
    address public admin;

    mapping(address => uint256) public balances;
    uint256 public totalDeposit;
    uint256 public accumulatedFees;

    // 1. 費率與時間鎖
    uint256 public feeRate = 100; // 目前費率 (Basis Points)
    uint256 public constant MAX_FEE_RATE = 1000; // 上限 10%
    uint256 public constant TIMELOCK_DURATION = 2 days; // 鎖定時間

    // 用於記錄「待生效」的費率更新
    uint256 public pendingFeeRate;
    uint256 public feeRateEffectiveTime; // 生效時間戳 (0 代表無待處理更新)

    // 2. 暫停與清算狀態
    bool public paused;
    bool public isShutdown;

    // 3. 名單管理
    mapping(address => bool) public isVIP;
    mapping(address => bool) public isBlacklisted;

    // --- 事件 ---
    event Deposit(address indexed user, uint256 amount, uint256 fee);
    event Withdraw(address indexed user, uint256 amount);
    event TransferInternal(address indexed from, address indexed to, uint256 amount); // 新增：內部轉帳事件
    
    event FeeRateQueued(uint256 newRate, uint256 effectiveTime);
    event FeeRateExecuted(uint256 newRate);
    
    event Paused(bool state);
    event BankShutdown(uint256 timestamp);
    
    event VIPStatusChanged(address indexed user, bool status);
    event BlacklistStatusChanged(address indexed user, bool status);

    event RefundIssued(address indexed user, uint256 amount);
    event RefundFailed(address indexed user, uint256 amount, string reason);

    // --- 修飾符 ---
    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    modifier whenActive() {
        require(!paused, "System is paused");
        require(!isShutdown, "Bank is shutting down");
        _;
    }

    modifier notBlacklisted() {
        require(!isBlacklisted[msg.sender], "Address is blacklisted");
        _;
    }

    constructor(address _tokenAddress) {
        authorizedToken = IERC20(_tokenAddress);
        admin = msg.sender;
    }

    // ============================================================
    // 功能 1: 存款
    // ============================================================
    function deposit(uint256 _amount) external whenActive notBlacklisted {
        require(_amount > 0, "Amount > 0");

        uint256 balanceBefore = authorizedToken.balanceOf(address(this));
        bool success = authorizedToken.transferFrom(msg.sender, address(this), _amount);
        require(success, "Transfer failed");
        uint256 received = authorizedToken.balanceOf(address(this)) - balanceBefore;

        uint256 fee = 0;
        if (!isVIP[msg.sender]) {
            fee = (received * feeRate) / 10000;
        }
        uint256 amountAfterFee = received - fee;

        balances[msg.sender] += amountAfterFee;
        totalDeposit += amountAfterFee;
        accumulatedFees += fee;

        emit Deposit(msg.sender, amountAfterFee, fee);
    }

    // ============================================================
    // 功能 2: 提款
    // ============================================================
    function withdraw(uint256 _amount) external notBlacklisted {
        require(balances[msg.sender] >= _amount, "Insufficient balance");
        
        balances[msg.sender] -= _amount;
        totalDeposit -= _amount;

        bool success = authorizedToken.transfer(msg.sender, _amount);
        require(success, "Transfer failed");

        emit Withdraw(msg.sender, _amount);
    }

    // ============================================================
    // 功能 3: 內部轉帳 (新增功能)
    // ============================================================
    function transfer(address _to, uint256 _amount) external notBlacklisted whenActive {
        require(_to != address(0), "Invalid recipient");
        require(_to != msg.sender, "Cannot transfer to self");
        require(_amount > 0, "Amount > 0");
        require(balances[msg.sender] >= _amount, "Insufficient balance");
        require(!isBlacklisted[_to], "Recipient is blacklisted"); // 禁止轉給黑名單

        // 內部帳本扣款與入帳
        balances[msg.sender] -= _amount;
        balances[_to] += _amount;

        emit TransferInternal(msg.sender, _to, _amount);
    }

    // ============================================================
    // 功能 4: 批次退款 (Fault Tolerant)
    // ============================================================
    function batchRefund(address[] calldata _users) external onlyAdmin {
        require(isShutdown, "Not in shutdown mode");

        for (uint256 i = 0; i < _users.length; i++) {
            address user = _users[i];
            uint256 amount = balances[user];

            if (amount > 0) {
                balances[user] = 0;
                totalDeposit -= amount;

                (bool success, bytes memory data) = address(authorizedToken).call(
                    abi.encodeWithSelector(IERC20.transfer.selector, user, amount)
                );

                if (success && (data.length == 0 || abi.decode(data, (bool)))) {
                    emit RefundIssued(user, amount);
                } else {
                    // 轉帳失敗，回滾帳本
                    balances[user] = amount;
                    totalDeposit += amount;
                    emit RefundFailed(user, amount, "Transfer failed");
                }
            }
        }
    }

    // ============================================================
    // 功能 5: 時間鎖費率調整 (Timelock)
    // ============================================================
    function queueFeeRateUpdate(uint256 _newRate) external onlyAdmin {
        require(_newRate <= MAX_FEE_RATE, "Rate too high");
        pendingFeeRate = _newRate;
        feeRateEffectiveTime = block.timestamp + TIMELOCK_DURATION;
        emit FeeRateQueued(_newRate, feeRateEffectiveTime);
    }

    function executeFeeRateUpdate() external onlyAdmin {
        require(feeRateEffectiveTime != 0, "No pending update");
        require(block.timestamp >= feeRateEffectiveTime, "Timelock not expired");

        feeRate = pendingFeeRate;
        feeRateEffectiveTime = 0;
        pendingFeeRate = 0;

        emit FeeRateExecuted(feeRate);
    }

    // ============================================================
    // 其他管理員功能
    // ============================================================
    function setBlacklist(address _user, bool _status) external onlyAdmin {
        isBlacklisted[_user] = _status;
        emit BlacklistStatusChanged(_user, _status);
    }

    function setPaused(bool _state) external onlyAdmin {
        paused = _state;
        emit Paused(_state);
    }

    function setVIP(address _user, bool _status) external onlyAdmin {
        isVIP[_user] = _status;
        emit VIPStatusChanged(_user, _status);
    }

    function triggerShutdown() external onlyAdmin {
        isShutdown = true;
        paused = true;
        emit BankShutdown(block.timestamp);
    }

    function adminClaimFees() external onlyAdmin {
        uint256 amount = accumulatedFees;
        accumulatedFees = 0;
        authorizedToken.transfer(admin, amount);
    }
}