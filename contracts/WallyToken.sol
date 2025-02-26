// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/* -----------------------------------------------------
 * Custom Errors
 * ---------------------------------------------------- */
error TradingDisabled();
error BlacklistedSender();
error BlacklistedRecipient();
error ExceedsMaxTx();
error SniperBuyBlocked();
error MustWaitCooldown();
error ApproveNonZero();
error CurrentAllowanceNonZero();     // H001: Clearer error naming
error NewAllowanceNonZero();         // H001: Added separate error for clarity
error MustZeroAllowanceFirst();      // G002: Custom error instead of string revert
error InvalidZeroAddress();          // G004: Custom error instead of long require string
error ETHTransferFailed();           // G004: Custom error instead of long require string

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}
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
        returns (uint amountToken, uint amountETH, uint liquidity);
}

/**
 * @title WallyToken
 * @dev Zero-tax ERC20. Uses AccessControl for admin. Anti-sniping logic, front-running approve fix, etc.
 */
contract WallyToken is ERC20, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    bytes32 private constant _ADMIN_ROLE  = keccak256("ADMIN_ROLE");
    bytes32 private constant _MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 private constant _BURNER_ROLE = keccak256("BURNER_ROLE");

    uint256 private constant _INITIAL_SUPPLY = 20e9 * 1e18; 

    address private immutable _daoAddress;

    IUniswapV2Router02 private _uniswapV2Router;
    address private _uniswapV2Pair;

    struct UserData {
        bool blacklisted;
        uint256 lastTx;
    }
    mapping(address user => UserData) private _userData;

    bool private _tradingEnabled;
    bool private _sniperProtectionEnabled;
    uint256 private _snipeTime = 30;       
    uint256 private _launchTimestamp;

    bool private _cooldownEnabled;
    uint256 private _cooldownTime = 30;    

    uint256 private _maxTxAmount; 

    // Event declarations
    event AllowanceChanged(address indexed owner, address indexed spender, uint256 oldAmount, uint256 newAmount);
    event TradingEnabledSet(bool indexed enabled);
    event SniperProtectionSet(bool indexed enabled, uint256 indexed timeSeconds);
    event CooldownSet(bool indexed enabled, uint256 indexed timeSeconds);
    event MaxTxAmountSet(uint256 indexed newMaxTx);
    event UserBlacklistedSet(address indexed user, bool indexed isBlacklisted);
    event TokensRescued(address indexed token, uint256 amount, address indexed to);
    event LiquidityAddRequested(address indexed admin, address indexed to, uint256 tokenAmountIn, uint256 ethAmount);
    event LiquidityAdded(address indexed to, uint256 tokenAmount, uint256 ethAmount, uint256 liquidity);
    event Minted(address indexed to, uint256 amount);
    event Burned(address indexed from, uint256 amount);
    event ReceivedEther(address indexed from, uint256 amount);
    event TokenRescueCompleted(address indexed token, address indexed from, address indexed to, uint256 amount);
    event TransferBlocked(address indexed from, address indexed to, string reason);
    event CooldownEnforced(address indexed sender, uint256 lastTx, uint256 cooldownTime);
    event SniperBlocked(address indexed from, address indexed to, uint256 timestamp);
    event MaxTxLimitReached(address indexed from, address indexed to, uint256 amount, uint256 maxAmount);

    constructor(address uniswapV2Router_, address daoAddress_)
        payable
        ERC20("Wally Token", "TWG")
    {
        // G004: Using custom errors instead of require strings
        if (uniswapV2Router_ == address(0)) revert InvalidZeroAddress();
        if (daoAddress_ == address(0)) revert InvalidZeroAddress();

        // G005: Cache _daoAddress for multiple uses
        address daoAddress = daoAddress_;
        _daoAddress = daoAddress;

        _mint(msg.sender, _INITIAL_SUPPLY);

        // Use cached daoAddress
        _grantRole(_ADMIN_ROLE, daoAddress);
        _setRoleAdmin(_MINTER_ROLE, _ADMIN_ROLE);
        _setRoleAdmin(_BURNER_ROLE, _ADMIN_ROLE);

        // G005: Cache router instance
        IUniswapV2Router02 router = IUniswapV2Router02(uniswapV2Router_);
        _uniswapV2Router = router;
        address factory = router.factory();
        address weth = router.WETH();

        // G001: Cache address(this)
        address self = address(this);
        _uniswapV2Pair = IUniswapV2Factory(factory).createPair(self, weth);

        _maxTxAmount = 0;
        _tradingEnabled = false;
        _sniperProtectionEnabled = false;
        _cooldownEnabled = false;
    }

    /**
     * @dev Approve fix for front-running (H001).
     * Requires setting allowance to 0 first before setting a new non-zero value.
     */
    function approve(address spender, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        // H001: Front-running protection improved
        // Must zero out old allowance before setting new, or revert
        uint256 current = allowance(msg.sender, spender);
        // G003: Split revert statements for better gas efficiency
        if (current != 0) {
            if (amount != 0) {
                revert CurrentAllowanceNonZero();
            }
        }
        
        // L002: Event before changing allowance
        emit AllowanceChanged(msg.sender, spender, current, amount);
        return super.approve(spender, amount);
    }

    // Force partial allowance changes to revert
    function increaseAllowance(address /*spender*/, uint256 /*addedValue*/)
        public
        pure
        returns (bool)
    {
        // G002: Using custom error instead of string
        revert MustZeroAllowanceFirst();
        // This line is unreachable but added for clarity with returns type
        return false;
    }
    
    function decreaseAllowance(address /*spender*/, uint256 /*subtractedValue*/)
        public
        pure
        returns (bool)
    {
        // G002: Using custom error instead of string
        revert MustZeroAllowanceFirst();
        // This line is unreachable but added for clarity with returns type
        return false;
    }

    // Mint & Burn
    function mint(address to, uint256 amount) external nonReentrant onlyRole(_MINTER_ROLE) {
        if (to == address(0)) revert InvalidZeroAddress();
        _mint(to, amount);
        emit Minted(to, amount);
    }

    function burn(uint256 amount) external nonReentrant onlyRole(_BURNER_ROLE) {
        _burn(_msgSender(), amount);
        emit Burned(_msgSender(), amount);
    }

    // Setters - L001: Fixed function returns with no return issue
    function setTradingEnabled(bool enabled)
        external
        nonReentrant
        onlyRole(_ADMIN_ROLE)
    {
        // Cache roles to save gas
        bytes32 adminRole = _ADMIN_ROLE;
        
        // G005: Cache storage variables
        bool tradingEnabled = _tradingEnabled;
        
        // Only update if value is different to save gas (avoid Gsreset)
        if (tradingEnabled != enabled) {
            _tradingEnabled = enabled;
            emit TradingEnabledSet(enabled);
            
            // G005: Cache _sniperProtectionEnabled
            bool sniperProtection = _sniperProtectionEnabled;
            if (enabled && sniperProtection) {
                // Document time manipulation concerns
                // I002: block.timestamp can be manipulated by miners within certain bounds
                // but for vesting periods over days/weeks, this limitation is acceptable
                _launchTimestamp = block.timestamp;
            }
        }
    }

    function setSniperProtection(bool enabled, uint256 timeSeconds)
        external
        nonReentrant
        onlyRole(_ADMIN_ROLE)
    {
        // Cache roles to save gas
        bytes32 adminRole = _ADMIN_ROLE;
        
        // G005: Cache storage variables
        bool sniperProtection = _sniperProtectionEnabled;
        uint256 snipeTime = _snipeTime;
        bool updated = false;
        
        // Only update if value is different to save gas (avoid Gsreset)
        if (sniperProtection != enabled) {
            _sniperProtectionEnabled = enabled;
            updated = true;
        }

        // Only update if value is different to save gas (avoid Gsreset)
        if (snipeTime != timeSeconds) {
            _snipeTime = timeSeconds;
            updated = true;
        }

        // Only emit event if something changed
        if (updated) {
            emit SniperProtectionSet(enabled, timeSeconds);
        }
    }

    function setCooldownConfig(bool enabled, uint256 cooldownSec)
        external
        nonReentrant
        onlyRole(_ADMIN_ROLE)
    {
        // Cache roles to save gas
        bytes32 adminRole = _ADMIN_ROLE;
        
        // G005: Cache storage variables
        bool cooldownEnabled = _cooldownEnabled;
        uint256 cooldownTime = _cooldownTime;
        bool updated = false;
        
        // Only update if value is different to save gas (avoid Gsreset)
        if (cooldownEnabled != enabled) {
            _cooldownEnabled = enabled;
            updated = true;
        }
        
        // Only update if value is different to save gas (avoid Gsreset)
        if (cooldownTime != cooldownSec) {
            _cooldownTime = cooldownSec;
            updated = true;
        }
        
        // Only emit event if something changed
        if (updated) {
            emit CooldownSet(enabled, cooldownSec);
        }
    }

    function setMaxTxAmount(uint256 maxTx)
        external
        nonReentrant
        onlyRole(_ADMIN_ROLE)
    {
        // Cache roles to save gas
        bytes32 adminRole = _ADMIN_ROLE;
        
        // G005: Cache storage variables
        uint256 maxTxAmount = _maxTxAmount;
        
        // Only update if value is different to save gas (avoid Gsreset)
        if (maxTxAmount != maxTx) {
            _maxTxAmount = maxTx;
            emit MaxTxAmountSet(maxTx);
        }
    }

    function setBlacklist(address user, bool blacklisted_)
        external
        nonReentrant
        onlyRole(_ADMIN_ROLE)
    {
        if (user == address(0)) revert InvalidZeroAddress();
        
        UserData storage data = _userData[user];
        if (data.blacklisted != blacklisted_) {
            data.blacklisted = blacklisted_;
            emit UserBlacklistedSet(user, blacklisted_);
        }
    }

    // Public getters with explicit return for clarity - L001: Fixed function returns with no return
    function daoAddress() external view returns (address) {
        return _daoAddress;
    }
    
    function uniswapV2Router() external view returns (address) {
        return address(_uniswapV2Router);
    }
    
    function uniswapV2Pair() external view returns (address) {
        return _uniswapV2Pair;
    }
    
    function tradingEnabled() external view returns (bool) {
        return _tradingEnabled;
    }
    
    function sniperProtectionEnabled() external view returns (bool) {
        return _sniperProtectionEnabled;
    }
    
    function snipeTime() external view returns (uint256) {
        return _snipeTime;
    }
    
    function launchTimestamp() external view returns (uint256) {
        return _launchTimestamp;
    }
    
    function cooldownEnabled() external view returns (bool) {
        return _cooldownEnabled;
    }
    
    function cooldownTime() external view returns (uint256) {
        return _cooldownTime;
    }
    
    function maxTxAmount() external view returns (uint256) {
        return _maxTxAmount;
    }
    
    function isBlacklisted(address user) external view returns (bool) {
        return _userData[user].blacklisted;
    }

    // Add Liquidity - using nonReentrant as first modifier for better safety
    function addLiquidityETH(
        address to,
        uint256 tokenAmountIn,
        uint256 tokenAmountMin,
        uint256 ethAmountMin,
        uint256 deadline
    )
        external
        payable  // Added payable keyword
        nonReentrant
        onlyRole(_ADMIN_ROLE)
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)
    {
        if (to == address(0)) revert InvalidZeroAddress();
        
        // Cache admin role
        bytes32 adminRole = _ADMIN_ROLE;
        
        emit LiquidityAddRequested(msg.sender, to, tokenAmountIn, msg.value);

        // G001: Cache address(this)
        address self = address(this);
        
        // G005: Cache router
        IUniswapV2Router02 router = _uniswapV2Router;

        // H001: Set allowance to 0 first
        _approve(self, address(router), 0);
        // Now set to desired amount
        _approve(self, address(router), tokenAmountIn);

        (amountToken, amountETH, liquidity) = router.addLiquidityETH{value: msg.value}(
            self,
            tokenAmountIn,
            tokenAmountMin,
            ethAmountMin,
            to,
            deadline
        );

        emit LiquidityAdded(to, amountToken, amountETH, liquidity);
        return (amountToken, amountETH, liquidity);
    }

    /**
     * @dev Hook to enforce anti-bot checks before any non-mint/non-burn transfer.
     * G003: This function is called multiple times, so it should not be inlined
     * I002: This function uses block.timestamp which can be manipulated by miners within certain bounds
     *       but for the purposes of these protection mechanisms, the limitations are acceptable
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override
        virtual
    {
        // Call parent implementation
        super._beforeTokenTransfer(from, to, amount);
        
        // Only apply checks if normal transfer
        if (from != address(0) && to != address(0) && amount != 0) {
            // Cache admin role and contract address to save gas
            bytes32 adminRole = _ADMIN_ROLE;
            address self = address(this);
            address uniswapPair = _uniswapV2Pair;
            
            // Cache user data to avoid multiple SLOADs
            UserData storage senderData = _userData[from];
            UserData storage recipientData = _userData[to];

            if (senderData.blacklisted) {
                emit TransferBlocked(from, to, "Sender blacklisted");
                revert BlacklistedSender();
            }
            
            if (recipientData.blacklisted) {
                emit TransferBlocked(from, to, "Recipient blacklisted");
                revert BlacklistedRecipient();
            }

            // G005: Cache storage variables
            bool tradingActive = _tradingEnabled;
            if (!tradingActive) {
                bool fromIsAdmin = hasRole(adminRole, from);
                bool toIsAdmin   = hasRole(adminRole, to);
                if (!fromIsAdmin && !toIsAdmin) {
                    emit TransferBlocked(from, to, "Trading disabled");
                    revert TradingDisabled();
                }
            }

            // G005: Cache storage variables
            uint256 localMaxTx = _maxTxAmount;
            if (localMaxTx != 0 && amount > localMaxTx) {
                emit MaxTxLimitReached(from, to, amount, localMaxTx);
                revert ExceedsMaxTx();
            }

            // G005: Cache storage variables
            bool sniperOn = _sniperProtectionEnabled;
            uint256 launchTimestamp = _launchTimestamp;
            uint256 snipeTime = _snipeTime;
            
            if (
                sniperOn &&
                tradingActive &&
                launchTimestamp != 0 &&
                // I002: block.timestamp can be manipulated by miners but acceptable for this use case
                block.timestamp <= (launchTimestamp + snipeTime)
            ) {
                // "buy" from Uniswap pair
                if (from == uniswapPair) {
                    emit SniperBlocked(from, to, block.timestamp);
                    revert SniperBuyBlocked();
                }
            }

            // G005: Cache storage variables
            bool cooldownOn = _cooldownEnabled;
            if (cooldownOn) {
                bool fromIsAdmin_ = hasRole(adminRole, from);
                bool toIsAdmin_   = hasRole(adminRole, to);

                // If neither side is admin and it's not a direct swap from/to Uniswap, enforce cooldown
                if (!fromIsAdmin_ && !toIsAdmin_ && from != uniswapPair && to != uniswapPair) {
                    uint256 lastTx = senderData.lastTx;
                    // G005: Cache storage variables
                    uint256 cooldownTime = _cooldownTime;
                    
                    // I002: block.timestamp can be manipulated by miners but acceptable for this use case
                    if (block.timestamp < (lastTx + cooldownTime)) {
                        emit CooldownEnforced(from, lastTx, cooldownTime);
                        revert MustWaitCooldown();
                    }
                    
                    // I002: block.timestamp can be manipulated by miners but acceptable for this use case
                    senderData.lastTx = block.timestamp;
                }
            }
        }
        // Fixed infinite recursion bug - removed recursive call to _beforeTokenTransfer
    }

    // Rescue functions - with nonReentrant as first modifier for better safety
    function rescueTokens(address tokenAddress, uint256 amount, address to)
        external
        nonReentrant
        onlyRole(_ADMIN_ROLE)
    {
        if (tokenAddress == address(0)) revert InvalidZeroAddress();
        if (to == address(0)) revert InvalidZeroAddress();
        
        // Cache address(this) to save gas
        address self = address(this);
        
        // Using SafeERC20 to handle non-standard ERC20 implementations safely
        IERC20 token = IERC20(tokenAddress);
        
        // Get balance before transfer
        uint256 balanceBefore = token.balanceOf(self);
        
        // Check if contract has enough tokens
        if (balanceBefore < amount) revert("Insufficient token balance");
        
        // Use safeTransfer from SafeERC20 to handle various edge cases
        token.safeTransfer(to, amount);
        
        emit TokensRescued(tokenAddress, amount, to);
        
        // Additional event to log the rescue details
        emit TokenRescueCompleted(tokenAddress, self, to, amount);
    }
    
    // Events for TokenRescue
    event TokenRescueCompleted(address indexed token, address indexed from, address indexed to, uint256 amount);

    function rescueETH(address payable to, uint256 amount)
        external
        payable // Added payable keyword
        nonReentrant
        onlyRole(_ADMIN_ROLE)
    {
        if (to == address(0)) revert InvalidZeroAddress();
        
        // Cache address(this) to save gas
        address self = address(this);
        uint256 balance = self.balance;
        
        // Ensure contract has enough ETH
        if (balance < amount) revert("Insufficient ETH balance");
        
        // Using low-level call for ETH transfer
        (bool success, ) = to.call{value: amount}("");
        
        // Must check if transfer was successful
        if (!success) revert ETHTransferFailed();
        
        // No need to add block.timestamp to events - it's included by default
        emit TokensRescued(address(0), amount, to);
    }

    receive() external payable {
        emit ReceivedEther(msg.sender, msg.value);
    }
}
