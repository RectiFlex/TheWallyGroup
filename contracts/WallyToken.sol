// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @dev Interface for Uniswap V2 Factory
 */
interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

/**
 * @dev Interface for Uniswap V2 Router
 */
interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    )
        external
        payable
        returns (
            uint amountToken,
            uint amountETH,
            uint liquidity
        );
}

/**
 * @title WallyToken
 * @notice 
 *  - Zero-tax ERC20 token
 *  - **AccessControl** with a designated DAO as `ADMIN_ROLE` (not the deployer EOA)
 *  - **Advanced Anti-Sniping**: (launchBlock sniper checks, optional cooldown)
 *  - Basic anti-bot features: (trading toggle, blacklist, max tx limit)
 *  - Liquidity management (Uniswap V2)
 *  - Rescue functions for stuck tokens/ETH
 *
 * @dev IMPORTANT: The DAO address must be a **secure** address (multi-sig or official DAO).
 */
contract WallyToken is ERC20, AccessControl, ReentrancyGuard {
    // ---------- Roles ----------
    bytes32 public constant ADMIN_ROLE  = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    // ---------- Supply Constants ----------
    uint256 public constant INITIAL_SUPPLY = 20_000_000_000 * 10**18; // 20B tokens, 18 decimals

    // ---------- DAO Address ----------
    // Replace with your actual DAO (e.g., multi-sig or official Aragon DAO Agent).
    address public constant DAO_ADDRESS = 0x633ea8fe424CD65AD4D4826e6581273afd06B8Ef;

    // ---------- Uniswap V2 Addresses ----------
    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;

    // ---------- Basic Anti-Bot State ----------
    bool public tradingEnabled = false;         // If false, only ADMIN_ROLE can transfer.
    mapping(address => bool) public blacklist;  // Blacklisted addresses cannot transfer.
    uint256 public maxTxAmount;                 // 0 => no limit.

    // ---------- Advanced Anti-Sniping State ----------
    bool public sniperProtectionEnabled = false; // If true, checks snipe blocks.
    uint256 public snipeBlocks = 2;             // Number of blocks after launch to block bot buys.
    uint256 public launchBlock;                 // Recorded when trading is first enabled.

    // ---------- Optional Cooldown State ----------
    bool public cooldownEnabled = false;         // If true, enforces time delay per address.
    uint256 public cooldownTime = 30;            // E.g. 30s cooldown
    mapping(address => uint256) public lastTxTimestamp; // Tracks last tx time

    // ---------- Events ----------
    event TradingEnabled(bool enabled);
    event Blacklisted(address indexed account, bool isBlacklisted);
    event MaxTxAmountUpdated(uint256 newMaxTx);
    event SniperProtectionUpdated(bool enabled, uint256 snipeBlocks);
    event CooldownUpdated(bool enabled, uint256 cooldownTime);

    /**
     * @dev Constructor
     *  1) Mints the entire supply to the deployer (msg.sender).
     *  2) Sets up roles so that only the DAO address has ADMIN_ROLE.
     *  3) Creates a Uniswap V2 pair for (TWG / WETH).
     *  4) Leaves the deployer with NO admin privileges by default, fulfilling the requirement 
     *     that the DAO is the sole admin from the start.
     * 
     * @param _uniswapV2Router Address of the Uniswap V2 router (e.g., 0x7a250d563...)
     */
    constructor(address _uniswapV2Router) ERC20("Wally Token", "TWG") {
        require(_uniswapV2Router != address(0), "Router cannot be zero address");

        // -------------------------
        // 1) Mint initial supply
        // -------------------------
        _mint(msg.sender, INITIAL_SUPPLY);

        // -------------------------
        // 2) Setup roles
        // -------------------------
        // The DAO is the permanent admin
        _grantRole(ADMIN_ROLE, DAO_ADDRESS);

        // Optionally, the DAO can grant MINTER_ROLE / BURNER_ROLE to specific addresses
        _setRoleAdmin(MINTER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(BURNER_ROLE, ADMIN_ROLE);

        // Note: We do NOT assign ADMIN_ROLE to msg.sender (the deployer),
        // ensuring that only the DAO address has admin privileges from inception.

        // -------------------------
        // 3) Setup Uniswap
        // -------------------------
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        address factory = uniswapV2Router.factory();
        address weth = uniswapV2Router.WETH();

        uniswapV2Pair = IUniswapV2Factory(factory).createPair(address(this), weth);

        // -------------------------
        // 4) Default settings
        // -------------------------
        maxTxAmount = 0; // No max limit by default
    }

    // -------------------------------------------------
    //   Mint & Burn (Controlled by MINTER/BURNER)
    // -------------------------------------------------
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function burn(uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(_msgSender(), amount);
    }

    // -------------------------------------------------
    //   Trading Toggle & Anti-Sniping Setup (ADMIN)
    // -------------------------------------------------

    /**
     * @dev Enables or disables trading. If enabling, records the `launchBlock` 
     *      for anti-sniping logic if `sniperProtectionEnabled` is true.
     */
    function setTradingEnabled(bool _enabled) external onlyRole(ADMIN_ROLE) {
        tradingEnabled = _enabled;

        // If turning on trading and sniperProtection is active, record the launch block.
        if (_enabled && sniperProtectionEnabled) {
            launchBlock = block.number;
        }

        emit TradingEnabled(_enabled);
    }

    /**
     * @dev Turn sniper protection on or off, and set how many blocks to protect.
     */
    function setSniperProtection(bool _enabled, uint256 _snipeBlocks)
        external
        onlyRole(ADMIN_ROLE)
    {
        sniperProtectionEnabled = _enabled;
        snipeBlocks = _snipeBlocks;
        emit SniperProtectionUpdated(_enabled, _snipeBlocks);
    }

    /**
     * @dev Toggle cooldown enforcement and set the cooldown duration in seconds.
     */
    function setCooldownConfig(bool _enabled, uint256 _cooldownTime)
        external
        onlyRole(ADMIN_ROLE)
    {
        cooldownEnabled = _enabled;
        cooldownTime = _cooldownTime;
        emit CooldownUpdated(_enabled, _cooldownTime);
    }

    // -------------------------------------------------
    //   Blacklist & Max Tx (ADMIN)
    // -------------------------------------------------

    function setBlacklist(address account, bool isBlacklisted)
        external
        onlyRole(ADMIN_ROLE)
    {
        blacklist[account] = isBlacklisted;
        emit Blacklisted(account, isBlacklisted);
    }

    function setMaxTxAmount(uint256 _maxTxAmount) external onlyRole(ADMIN_ROLE) {
        maxTxAmount = _maxTxAmount;
        emit MaxTxAmountUpdated(_maxTxAmount);
    }

    // -------------------------------------------------
    //   Uniswap V2: Add Liquidity (ADMIN)
    // -------------------------------------------------

    /**
     * @dev Add liquidity (TWG / ETH) on Uniswap. Must transfer `tokenAmountIn` to
     *      this contract first, or do it in a two-transaction flow from a front-end.
     */
    function addLiquidityETH(
        address to,
        uint256 tokenAmountIn,
        uint256 tokenAmountMin,
        uint256 ethAmountMin,
        uint256 deadline
    )
        external
        payable
        nonReentrant
        onlyRole(ADMIN_ROLE)
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)
    {
        // Approve the router to spend tokens held by this contract
        _approve(address(this), address(uniswapV2Router), tokenAmountIn);

        (amountToken, amountETH, liquidity) = uniswapV2Router.addLiquidityETH{
            value: msg.value
        }(
            address(this),
            tokenAmountIn,
            tokenAmountMin,
            ethAmountMin,
            to,
            deadline
        );
    }

    // -------------------------------------------------
    //          Transfer Hook (Anti-Bot Logic)
    // -------------------------------------------------

    /**
     * @dev Hook to enforce:
     *  1) Trading toggle restrictions
     *  2) Blacklist checks
     *  3) Max transaction limit
     *  4) Sniper protection (blocks initial sniping within `snipeBlocks` of enabling)
     *  5) Optional per-address cooldown
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal {
        // 1) Prevent blacklisted addresses from sending/receiving
        require(!blacklist[from], "WallyToken: Sender blacklisted");
        require(!blacklist[to],   "WallyToken: Recipient blacklisted");

        // 2) If trading is disabled, only ADMIN_ROLE can transfer
        if (!tradingEnabled) {
            if (!hasRole(ADMIN_ROLE, from) && !hasRole(ADMIN_ROLE, to)) {
                revert("WallyToken: Trading disabled");
            }
        }

        // 3) Max transaction limit
        if (maxTxAmount > 0 && amount > maxTxAmount) {
            revert("WallyToken: Exceeds maxTxAmount");
        }

        // 4) Anti-Sniping: if sniperProtectionEnabled & trading is just enabled,
        //    block buys during the first `snipeBlocks` blocks
        if (
            sniperProtectionEnabled &&
            tradingEnabled &&
            launchBlock > 0 &&
            block.number <= (launchBlock + snipeBlocks)
        ) {
            // If this is a "buy" from the Uniswap Pair, block or revert
            // (One can also forcibly blacklist `to` if desired.)
            if (from == uniswapV2Pair) {
                revert("WallyToken: Sniper buy blocked");
            }
        }

        // 5) Cooldown: if enabled, require each address to wait `cooldownTime` 
        //    seconds between transfers (unless it's admin or a pair).
        if (cooldownEnabled) {
            // Exempt: admin or if from/to is the pair
            bool isExempt = hasRole(ADMIN_ROLE, from)
                || hasRole(ADMIN_ROLE, to)
                || from == uniswapV2Pair
                || to == uniswapV2Pair;
            
            if (!isExempt) {
                require(
                    block.timestamp >= lastTxTimestamp[from] + cooldownTime,
                    "WallyToken: Must wait for cooldown"
                );
                lastTxTimestamp[from] = block.timestamp;
            }
        }

    }

    // -------------------------------------------------
    //   Recover Stuck Tokens / ETH (ADMIN)
    // -------------------------------------------------

    function rescueTokens(address tokenAddress, uint256 amount, address to)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(to != address(0), "Invalid 'to'");
        ERC20(tokenAddress).transfer(to, amount);
    }

    function rescueETH(address payable to, uint256 amount)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(to != address(0), "Invalid 'to'");
        (bool success, ) = to.call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    // Accept ETH
    receive() external payable {}
}