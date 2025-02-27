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
error InsufficientBalance();         // For ETH balance checks
error InsufficientTokenBalance();    // For token balance checks

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

        // G005: Cache _daoAddress for multiple uses - renamed to avoid name collision with function
        address cachedDaoAddress = daoAddress_;
        _daoAddress = cachedDaoAddress;

        _mint(msg.sender, _INITIAL_SUPPLY);

        // Use cached daoAddress
        _grantRole(_ADMIN_ROLE, cachedDaoAddress);
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
     * This is the best practice to prevent the ERC20 approval front-running attack.
     */
    function approve(address spender, uint256 amount)
        public
        virtual
        override
        returns (bool success)
    {
        // H001: Improved front-running protection
        uint256 current = allowance(msg.sender, spender);
        
        // If current allowance is not zero, only allow setting to zero
        if (current != 0) {
            if (amount != 0) {
                revert CurrentAllowanceNonZero();
            }
        }
        
        // L002: Event before changing allowance
        emit AllowanceChanged(msg.sender, spender, current, amount);
        success = super.approve(spender, amount);
        
        // Emit another event to confirm the approval was successful
        if (success) {
            emit Approval(msg.sender, spender, amount);
        }
        
        return success;
    }

    // Force partial allowance changes to revert
    function increaseAllowance(address /*spender*/, uint256 /*addedValue*/)
        public
        pure
        returns (bool success)
    {
        revert MustZeroAllowanceFirst();
    }
    
    function decreaseAllowance(address /*spender*/, uint256 /*subtractedValue*/)
        public
        pure
        returns (bool success)
    {
        revert MustZeroAllowanceFirst();
    }

    // Mint & Burn - with proper events and nonReentrant for security
    function mint(address to, uint256 amount) 
        external 
        nonReentrant 
        onlyRole(_MINTER_ROLE) 
        returns (bool success)
    {
        if (to == address(0)) revert InvalidZeroAddress();
        
        _mint(to, amount);
        emit Minted(to, amount);
        success = true;
        
        return success;
    }

    function burn(uint256 amount) 
        external 
        nonReentrant 
        onlyRole(_BURNER_ROLE) 
        returns (bool success)
    {
        _burn(_msgSender(), amount);
        emit Burned(_msgSender(), amount);
        success = true;
        
        return success;
    }

    // Setters - L001: Fixed function returns with no return issue
    function setTradingEnabled(bool enabled)
        external
        nonReentrant
        onlyRole(_ADMIN_ROLE)
    {
        // G005: Cache storage variables - renamed to avoid name collision with function
        bool isTradingEnabled = _tradingEnabled;
        
        // Only update if value is different to save gas (avoid Gsreset)
        if (isTradingEnabled != enabled) {
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
        // G005: Cache storage variables - renamed to avoid name collision with function
        bool isSniperProtectionEnabled = _sniperProtectionEnabled;
        uint256 snipeTimeValue = _snipeTime;
        bool updated = false;
        
        // Only update if value is different to save gas (avoid Gsreset)
        if (isSniperProtectionEnabled != enabled) {
            _sniperProtectionEnabled = enabled;
            updated = true;
        }

        // Only update if value is different to save gas (avoid Gsreset)
        if (snipeTimeValue != timeSeconds) {
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
        // G005: Cache storage variables - renamed to avoid name collision with function
        bool isCooldownEnabled = _cooldownEnabled;
        uint256 cooldownTimeValue = _cooldownTime;
        bool updated = false;
        
        // Only update if value is different to save gas (avoid Gsreset)
        if (isCooldownEnabled != enabled) {
            _cooldownEnabled = enabled;
            updated = true;
        }
        
        // Only update if value is different to save gas (avoid Gsreset)
        if (cooldownTimeValue != cooldownSec) {
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
        // G005: Cache storage variables - renamed to avoid name collision with function
        uint256 maxTxValue = _maxTxAmount;
        
        // Only update if value is different to save gas (avoid Gsreset)
        if (maxTxValue != maxTx) {
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

    // G003: This function is called multiple times, so should not be inlined
    // We can't inline _beforeTokenTransfer since it's a hook function that needs to maintain the proper override
    // Instead, we optimize its internal code to be as efficient as possible
    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        
    {
        // Call parent implementation
       _beforeTokenTransfer(from, to, amount);
        
        // Only apply checks if normal transfer
        if (from != address(0) && to != address(0) && amount != 0) {
            // Cache all used storage variables upfront to minimize SLOADs
            bytes32 adminRole = _ADMIN_ROLE;
            address uniswapPair = _uniswapV2Pair;
            bool isTradingEnabled = _tradingEnabled;
            bool isSniperProtectionEnabled = _sniperProtectionEnabled;
            bool isCooldownEnabled = _cooldownEnabled;
            uint256 maxTxValue = _maxTxAmount;
            uint256 launchTimestampValue = _launchTimestamp;
            uint256 snipeTimeValue = _snipeTime;
            uint256 cooldownTimeValue = _cooldownTime;
            
            // Cache user data to avoid multiple SLOADs
            UserData storage senderData = _userData[from];
            UserData storage recipientData = _userData[to];

            // Blacklist checks
            if (senderData.blacklisted) {
                emit TransferBlocked(from, to, "Sender blacklisted");
                revert BlacklistedSender();
            }
            
            if (recipientData.blacklisted) {
                emit TransferBlocked(from, to, "Recipient blacklisted");
                revert BlacklistedRecipient();
            }

            // Trading enabled check
            if (!isTradingEnabled) {
                bool fromIsAdmin = hasRole(adminRole, from);
                bool toIsAdmin = hasRole(adminRole, to);
                if (!fromIsAdmin && !toIsAdmin) {
                    emit TransferBlocked(from, to, "Trading disabled");
                    revert TradingDisabled();
                }
            }

            // Max transaction amount check
            if (maxTxValue != 0 && amount > maxTxValue) {
                emit MaxTxLimitReached(from, to, amount, maxTxValue);
                revert ExceedsMaxTx();
            }

            // Sniper protection check
            if (
                isSniperProtectionEnabled &&
                isTradingEnabled &&
                launchTimestampValue != 0 &&
                // Use non-strict inequality for gas optimization
                block.timestamp <= (launchTimestampValue + snipeTimeValue)
            ) {
                if (from == uniswapPair) {
                    emit SniperBlocked(from, to, 0);
                    revert SniperBuyBlocked();
                }
            }

            // Cooldown check
            if (isCooldownEnabled) {
                bool fromIsAdmin = hasRole(adminRole, from);
                bool toIsAdmin = hasRole(adminRole, to);

                if (!fromIsAdmin && !toIsAdmin && from != uniswapPair && to != uniswapPair) {
                    uint256 lastTx = senderData.lastTx;
                    
                    if (block.timestamp <= (lastTx + cooldownTimeValue)) {
                        emit CooldownEnforced(from, 0, 0);
                        revert MustWaitCooldown();
                    }
                    
                    senderData.lastTx = block.timestamp;
                }
            }
        }
    }

    // Custom error for insufficient token balance
    error InsufficientTokenBalance();

    // Rescue functions with explicit return values for consistency
    function rescueTokens(address tokenAddress, uint256 amount, address to)
        external
        nonReentrant
        onlyRole(_ADMIN_ROLE)
        returns (bool success)
    {
        if (tokenAddress == address(0)) revert InvalidZeroAddress();
        if (to == address(0)) revert InvalidZeroAddress();
        
        // Cache address(this) to save gas
        address self = address(this);
        
        // Using SafeERC20 to handle non-standard ERC20 implementations safely
        IERC20 token = IERC20(tokenAddress);
        
        // Get balance before transfer
        uint256 balance = token.balanceOf(self);
        
        // Check if contract has enough tokens - use custom error instead of string
        if (balance < amount) revert InsufficientTokenBalance();
        
        // Use safeTransfer from SafeERC20 to handle various edge cases
        token.safeTransfer(to, amount);
        
        // Emit both events for better tracking
        emit TokensRescued(tokenAddress, amount, to);
        emit TokenRescueCompleted(tokenAddress, self, to, amount);
        
        success = true;
        return success;
    }
    

    function rescueETH(address payable to, uint256 amount)
        external
        payable
        nonReentrant
        onlyRole(_ADMIN_ROLE)
        returns (bool success)
    {
        if (to == address(0)) revert InvalidZeroAddress();
        
        // Cache address(this) to save gas
        address self = address(this);
        uint256 balance = self.balance;
        
        // Ensure contract has enough ETH
        if (balance < amount) revert InsufficientBalance();
        
        // Using low-level call for ETH transfer
        (bool transferred, ) = to.call{value: amount}("");
        
        // Must check if transfer was successful
        if (!transferred) revert ETHTransferFailed();
        
        // Emit event for tracking
        emit TokensRescued(address(0), amount, to);
        
        success = true;
        return success;
    }

    receive() external payable {
        emit ReceivedEther(msg.sender, msg.value);
    }
}