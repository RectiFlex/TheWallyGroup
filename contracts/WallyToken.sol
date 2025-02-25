// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
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

    constructor(address uniswapV2Router_, address daoAddress_)
        payable
        ERC20("Wally Token", "TWG")
    {
        require(uniswapV2Router_ != address(0), "Zero router");
        require(daoAddress_ != address(0), "Zero DAO");

        _daoAddress = daoAddress_;

        _mint(msg.sender, _INITIAL_SUPPLY);

        _grantRole(_ADMIN_ROLE, _daoAddress);
        _setRoleAdmin(_MINTER_ROLE, _ADMIN_ROLE);
        _setRoleAdmin(_BURNER_ROLE, _ADMIN_ROLE);

        IUniswapV2Router02 router = IUniswapV2Router02(uniswapV2Router_);
        _uniswapV2Router = router;
        address factory = router.factory();
        address weth = router.WETH();

        address self_ = address(this);
        _uniswapV2Pair = IUniswapV2Factory(factory).createPair(self_, weth);

        _maxTxAmount = 0;
        _tradingEnabled = false;
        _sniperProtectionEnabled = false;
        _cooldownEnabled = false;
    }

    /**
     * @dev Approve fix for front-running (H001).
     */
    function approve(address spender, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        uint256 current = allowance(msg.sender, spender);
        // Must zero out old allowance before setting new, or revert
        if (current != 0 && amount != 0) {
            revert ApproveNonZero();
        }
        return super.approve(spender, amount);
    }

    // Force partial allowance changes to revert
    function increaseAllowance(address /*spender*/, uint256 /*addedValue*/)
        public
        virtual
        returns (bool)
    {
        revert("Use approve() to set to 0 first");
    }
    function decreaseAllowance(address /*spender*/, uint256 /*subtractedValue*/)
        public
        virtual
        returns (bool)
    {
        revert("Use approve() to set to 0 first");
    }

    // Mint & Burn
    function mint(address to, uint256 amount) external onlyRole(_MINTER_ROLE) {
        _mint(to, amount);
        emit Minted(to, amount);
    }

    function burn(uint256 amount) external onlyRole(_BURNER_ROLE) {
        _burn(_msgSender(), amount);
        emit Burned(_msgSender(), amount);
    }

    // Setters
    function setTradingEnabled(bool enabled)
        external
        nonReentrant
        onlyRole(_ADMIN_ROLE)
    {
        if (_tradingEnabled != enabled) {
            _tradingEnabled = enabled;
            emit TradingEnabledSet(enabled);
            if (enabled && _sniperProtectionEnabled) {
                _launchTimestamp = block.timestamp; 
            }
        }
    }

    function setSniperProtection(bool enabled, uint256 timeSeconds)
        external
        nonReentrant
        onlyRole(_ADMIN_ROLE)
    {
        if (_sniperProtectionEnabled != enabled) {
            _sniperProtectionEnabled = enabled;
        }
        if (_snipeTime != timeSeconds) {
            _snipeTime = timeSeconds;
        }
        emit SniperProtectionSet(enabled, timeSeconds);
    }

    function setCooldownConfig(bool enabled, uint256 cooldownSec)
        external
        nonReentrant
        onlyRole(_ADMIN_ROLE)
    {
        if (_cooldownEnabled != enabled) {
            _cooldownEnabled = enabled;
        }
        if (_cooldownTime != cooldownSec) {
            _cooldownTime = cooldownSec;
        }
        emit CooldownSet(enabled, cooldownSec);
    }

    function setMaxTxAmount(uint256 maxTx)
        external
        nonReentrant
        onlyRole(_ADMIN_ROLE)
    {
        if (_maxTxAmount != maxTx) {
            _maxTxAmount = maxTx;
            emit MaxTxAmountSet(maxTx);
        }
    }

    function setBlacklist(address user, bool blacklisted_)
        external
        nonReentrant
        onlyRole(_ADMIN_ROLE)
    {
        UserData storage data = _userData[user];
        if (data.blacklisted != blacklisted_) {
            data.blacklisted = blacklisted_;
            emit UserBlacklistedSet(user, blacklisted_);
        }
    }

    // Public getters
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

    // Add Liquidity
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
        onlyRole(_ADMIN_ROLE)
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)
    {
        emit LiquidityAddRequested(msg.sender, to, tokenAmountIn, msg.value);

        address self_ = address(this);
        IUniswapV2Router02 router = _uniswapV2Router;

        _approve(self_, address(router), tokenAmountIn);

        (amountToken, amountETH, liquidity) = router.addLiquidityETH{value: msg.value}(
            self_,
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
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        virtual
    {
        // Only apply checks if normal transfer
        if (from != address(0) && to != address(0) && amount != 0) {
            UserData storage senderData = _userData[from];
            UserData storage recipientData = _userData[to];

            if (senderData.blacklisted) revert BlacklistedSender();
            if (recipientData.blacklisted) revert BlacklistedRecipient();

            bool tradingActive = _tradingEnabled;
            if (!tradingActive) {
                bool fromIsAdmin = hasRole(_ADMIN_ROLE, from);
                bool toIsAdmin   = hasRole(_ADMIN_ROLE, to);
                if (!fromIsAdmin && !toIsAdmin) {
                    revert TradingDisabled();
                }
            }

            uint256 localMaxTx = _maxTxAmount;
            if (localMaxTx != 0 && amount > localMaxTx) {
                revert ExceedsMaxTx();
            }

            bool sniperOn = _sniperProtectionEnabled;
            if (
                sniperOn &&
                tradingActive &&
                _launchTimestamp != 0 &&
                block.timestamp <= (_launchTimestamp + _snipeTime)
            ) {
                // "buy" from Uniswap pair
                if (from == _uniswapV2Pair) {
                    revert SniperBuyBlocked();
                }
            }

            bool cooldownOn = _cooldownEnabled;
            if (cooldownOn) {
                bool fromIsAdmin_ = hasRole(_ADMIN_ROLE, from);
                bool toIsAdmin_   = hasRole(_ADMIN_ROLE, to);

                // If neither side is admin and it's not a direct swap from/to Uniswap, enforce cooldown
                if (!fromIsAdmin_ && !toIsAdmin_ && from != _uniswapV2Pair && to != _uniswapV2Pair) {
                    uint256 lastTx = senderData.lastTx;
                    if (block.timestamp < (lastTx + _cooldownTime)) {
                        revert MustWaitCooldown();
                    }
                    senderData.lastTx = block.timestamp;
                }
            }
        }
        _beforeTokenTransfer(from, to, amount);
    }

    // Rescue
    function rescueTokens(address tokenAddress, uint256 amount, address to)
        external
        nonReentrant
        onlyRole(_ADMIN_ROLE)
    {
        require(to != address(0), "Zero 'to'");
        IERC20(tokenAddress).transfer(to, amount);
        emit TokensRescued(tokenAddress, amount, to);
    }

    function rescueETH(address payable to, uint256 amount)
        external
        payable
        nonReentrant
        onlyRole(_ADMIN_ROLE)
    {
        require(to != address(0), "Zero 'to'");
        emit TokensRescued(address(0), amount, to);

        (bool success, ) = to.call{value: amount}("");
        require(success, "ETH fail");
    }

    receive() external payable {
        emit ReceivedEther(msg.sender, msg.value);
    }
}