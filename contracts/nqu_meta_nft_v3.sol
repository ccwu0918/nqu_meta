// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4; // 指定 Solidity 版本，ERC721A 建議使用較新的版本

// ----------------------------------------------------------------------------
// 引入外部合約庫
// ----------------------------------------------------------------------------
// 1. ERC721A: Azuki 團隊開發的 Gas 優化版 ERC721 標準，大幅降低批量鑄造的費用
import "erc721a/contracts/ERC721A.sol";
// 2. Ownable: 權限控制合約，提供 onlyOwner 修飾詞，確保只有合約擁有者能執行特定功能
import "@openzeppelin/contracts/access/Ownable.sol";
// 3. ReentrancyGuard: 防重入攻擊合約，提供 nonReentrant 修飾詞，保護提款等敏感操作
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// 4. Strings: 用於處理數字轉字串的工具庫
import "@openzeppelin/contracts/utils/Strings.sol";

// ----------------------------------------------------------------------------
// 主合約定義
// 繼承順序：ERC721A (NFT標準), Ownable (權限), ReentrancyGuard (安全性)
// ----------------------------------------------------------------------------
contract NquMeta is ERC721A, Ownable, ReentrancyGuard {
    // 讓 uint256 類型可以使用 Strings 庫的方法 (例如 .toString())
    using Strings for uint256;

    // ------------------------------------------------------------------------
    // 狀態變數 (State Variables)
    // ------------------------------------------------------------------------
    
    // 販售狀態開關 (預設為 false 關閉)
    // true = 開啟販售, false = 暫停販售
    bool public _isSaleActive = false;

    // 盲盒開啟狀態開關 (預設為 false 未開啟)
    // true = 顯示真實圖片, false = 顯示盲盒封面
    bool public _revealed = false;

    // 常數設定 (Constants)
    // NFT 最大發行總量 (固定為 10，不可修改)
    uint256 public constant MAX_SUPPLY = 10;

    // 可調整的營運參數
    // 鑄造單價 (預設 0.0001 ETH)
    uint256 public mintPrice = 0.0001 ether;
    
    // 每個錢包地址最大持有數量限制
    uint256 public maxBalance = 1;
    
    // 單次交易最大鑄造數量限制
    uint256 public maxMint = 1;

    // Metadata 相關路徑設定
    // 基礎 URI (Base URI)，用於拼接真實 NFT 圖片路徑 (例如: ipfs://Qm.../)
    // 注意：這裡改為 public 以便前端能直接讀取預設值
    string public baseURI;
    
    // 盲盒 URI (Not Revealed URI)，當 _revealed 為 false 時回傳此路徑
    string public notRevealedUri;
    
    // Metadata 檔案副檔名 (預設為 .json)
    string public baseExtension = ".json";

    // 用於儲存特定 Token ID 的獨立 URI (較少使用，保留彈性)
    mapping(uint256 => string) private _tokenURIs;

    // ------------------------------------------------------------------------
    // 建構子 (Constructor)
    // 合約部署時執行一次
    // ------------------------------------------------------------------------
    constructor(string memory initBaseURI, string memory initNotRevealedUri)
        ERC721A("NQU Meta", "NQUCoin") // 設定 NFT 系列名稱與代號
        Ownable(msg.sender) // 設定部署者為合約擁有者 (Owner)
    {
        // 初始化圖片路徑
        setBaseURI(initBaseURI);
        setNotRevealedURI(initNotRevealedUri);
    }

    // ------------------------------------------------------------------------
    // 使用者功能 (User Functions)
    // ------------------------------------------------------------------------

    /**
     * @dev 公開鑄造函式 (Mint)
     * @param tokenQuantity 使用者欲鑄造的 NFT 數量
     */
    function mintNquMeta(uint256 tokenQuantity) public payable {
        // 檢查 1: 鑄造後總量不可超過最大發行量 (MAX_SUPPLY)
        // totalSupply() 是 ERC721A 提供的函式，回傳目前已鑄造總數
        require(
            totalSupply() + tokenQuantity <= MAX_SUPPLY,
            "Sale would exceed max supply" // 錯誤訊息：超過最大供應量
        );

        // 檢查 2: 必須在販售開啟狀態 (_isSaleActive 為 true)
        require(_isSaleActive, "Sale must be active to mint NQU Metas"); // 錯誤訊息：販售尚未開啟

        // 檢查 3: 限制單一錢包最大持有量
        // balanceOf(msg.sender) 查詢呼叫者目前的持有量
        require(
            balanceOf(msg.sender) + tokenQuantity <= maxBalance,
            "Sale would exceed max balance" // 錯誤訊息：超過錢包持有上限
        );

        // 檢查 4: 檢查發送的 ETH 金額是否足夠
        require(
            tokenQuantity * mintPrice <= msg.value,
            "Not enough ether sent" // 錯誤訊息：ETH 金額不足
        );

        // 檢查 5: 限制單次交易最大鑄造量
        require(tokenQuantity <= maxMint, "Can only mint 1 tokens at a time"); // 錯誤訊息：超過單次鑄造上限

        // 通過所有檢查後，執行內部鑄造函式
        _mintNquMeta(tokenQuantity);
    }

    /**
     * @dev 內部鑄造函式
     * @param tokenQuantity 鑄造數量
     */
    function _mintNquMeta(uint256 tokenQuantity) internal {
        // Gas 優化核心：直接呼叫 ERC721A 的 _safeMint
        // 這比傳統 ERC721 的 for 迴圈省下大量 Gas
        _safeMint(msg.sender, tokenQuantity);
    }

    /**
     * @dev 覆寫 (Override) 起始 Token ID
     * 預設 ERC721A 從 0 開始，這裡改為從 1 開始，以符合一般圖片編號習慣
     */
    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    /**
     * @dev 取得 Token Metadata URI
     * @param tokenId NFT 的編號
     * @return string 回傳完整的 Metadata 網址
     */
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        // 檢查該 Token ID 是否存在
        require(
            _exists(tokenId), 
            "ERC721Metadata: URI query for nonexistent token"
        );

        // 邏輯 1: 如果盲盒尚未開啟 (_revealed == false)
        // 直接回傳盲盒封面圖片路徑
        if (_revealed == false) {
            return notRevealedUri;
        }

        // 邏輯 2: 如果已開啟，組合真實路徑
        string memory _tokenURI = _tokenURIs[tokenId];
        string memory base = _baseURI();

        // 情況 A: 如果沒有設定 Base URI，直接回傳個別設定的 URI
        if (bytes(base).length == 0) {
            return _tokenURI;
        }
        // 情況 B: 如果有設定 Base URI 且有個別 URI，則拼接兩者
        if (bytes(_tokenURI).length > 0) {
            return string(abi.encodePacked(base, _tokenURI));
        }
        // 情況 C: 拼接 Base URI + Token ID + 副檔名 (最常見的情況)
        return
            string(abi.encodePacked(base, tokenId.toString(), baseExtension));
    }

    /**
     * @dev 內部函式：回傳 Base URI
     * ERC721 需要覆寫此函式
     */
    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    // ------------------------------------------------------------------------
    // 管理員功能 (Only Owner Functions)
    // 所有的函式都帶有 onlyOwner 修飾詞，確保安全性
    // ------------------------------------------------------------------------

    // 切換販售狀態 (開啟/關閉)
    function flipSaleActive() public onlyOwner {
        _isSaleActive = !_isSaleActive;
    }

    // 切換盲盒狀態 (開啟/關閉)
    function flipReveal() public onlyOwner {
        _revealed = !_revealed;
    }

    // 設定鑄造價格 (單位: Wei)
    function setMintPrice(uint256 _mintPrice) public onlyOwner {
        mintPrice = _mintPrice;
    }

    // 設定盲盒封面圖片路徑 (Not Revealed URI)
    function setNotRevealedURI(string memory _notRevealedURI) public onlyOwner {
        notRevealedUri = _notRevealedURI;
    }

    // 設定基礎圖片路徑 (Base URI)
    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        baseURI = _newBaseURI;
    }

    // 設定 Metadata 副檔名 (例如 ".json")
    function setBaseExtension(string memory _newBaseExtension)
        public
        onlyOwner
    {
        baseExtension = _newBaseExtension;
    }

    // 設定單一錢包最大持有量
    function setMaxBalance(uint256 _maxBalance) public onlyOwner {
        maxBalance = _maxBalance;
    }

    // 設定單次交易最大鑄造量
    function setMaxMint(uint256 _maxMint) public onlyOwner {
        maxMint = _maxMint;
    }

    /**
     * @dev 安全提款函式
     * 將合約內的所有 ETH 餘額提領到指定地址
     * @param to 接收 ETH 的錢包地址
     */
    function withdraw(address to) public onlyOwner nonReentrant {
        uint256 balance = address(this).balance; // 取得合約餘額
        
        // 使用 .call 取代 .transfer 以避免 Gas Limit 問題
        // 並搭配 nonReentrant 防止重入攻擊
        (bool success, ) = payable(to).call{value: balance}("");
        require(success, "Transfer failed"); // 確保轉帳成功
    }
}
