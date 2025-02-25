// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/* ---------------------------------
 * Custom Errors (saving gas vs. revert strings)
 * --------------------------------- */
error ZeroAmount();
error InvalidLockChoice();
error AlreadyWithdrawn();
error LockNotOver();
error InsufficientBalance();
error InvalidAddress();

/**
 * @title WallyStaking
 * @dev Stake Wally Tokens for fixed durations (3, 6, or 12 months) to earn APY-based rewards.
 *
 * Must be funded with enough TWG to cover principal + rewards.
 * Addresses many audit items: M001 (fees?), M002 (array length check), M003 (checking transfer), etc.
 */
contract WallyStaking is AccessControl, ReentrancyGuard {
    bytes32 internal constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    IERC20 internal immutable wallyToken;

    // Lock durations (internal, pinned)
    uint256 internal constant LOCK_3_MONTHS = 90 days;
    uint256 internal constant LOCK_6_MONTHS = 180 days;
    uint256 internal constant LOCK_12_MONTHS = 365 days;

    // APYs in basis points, e.g. 500 = 5%
    uint256 public apy3Months = 500;
    uint256 public apy6Months = 1000;
    uint256 public apy12Months = 1500;

    struct StakeInfo {
        uint256 amount;
        uint256 startTimestamp;
        uint256 lockDuration;
        uint256 apy; // basis points
        bool withdrawn;
    }

    // (I003) Named mapping parameter for >=0.8.18
    mapping(address user => StakeInfo[]) internal _stakes;

    event Staked(address indexed user, uint256 amount, uint256 lockDuration, uint256 apy);
    event Withdrawn(address indexed user, uint256 stakeIndex, uint256 reward);

    constructor(address _wallyToken, address _admin) payable { // (G008) constructor payable
        if (_wallyToken == address(0)) revert InvalidAddress();
        if (_admin == address(0)) revert InvalidAddress();

        wallyToken = IERC20(_wallyToken);
        _grantRole(ADMIN_ROLE, _admin);
    }

    /**
     * @dev Stake a specific `amount` of TWG for one of the fixed durations (3, 6, 12 months).
     */
    function stake(uint256 amount, uint256 lockChoice) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        (uint256 chosenLock, uint256 chosenAPY) = _getLockInfo(lockChoice);

        // Transfer from user to contract (M003 => check bool return)
        bool success = wallyToken.transferFrom(msg.sender, address(this), amount);
        if (!success) revert InsufficientBalance();

        _stakes[msg.sender].push(StakeInfo({
            amount: amount,
            startTimestamp: block.timestamp, // (I002) approximate time
            lockDuration: chosenLock,
            apy: chosenAPY,
            withdrawn: false
        }));

        emit Staked(msg.sender, amount, chosenLock, chosenAPY);
    }

    /**
     * @dev Withdraw staked tokens + reward after lock period ends.
     */
    function withdraw(uint256 stakeIndex) external nonReentrant {
        StakeInfo[] storage userStakes = _stakes[msg.sender];
        // (M002) check array length
        if (stakeIndex >= userStakes.length) revert InvalidLockChoice();

        StakeInfo storage userStake = userStakes[stakeIndex];
        if (userStake.withdrawn) revert AlreadyWithdrawn();

        uint256 unlockTime = userStake.startTimestamp + userStake.lockDuration;
        if (block.timestamp < unlockTime) revert LockNotOver();

        uint256 principal = userStake.amount;
        uint256 timeStaked = userStake.lockDuration; 
        // (M004) typical formula for APY
        uint256 reward = (principal * userStake.apy * timeStaked) / (365 days * 10000);

        userStake.withdrawn = true;

        uint256 totalPayment = principal + reward;
        if (wallyToken.balanceOf(address(this)) < totalPayment) revert InsufficientBalance();

        bool success = wallyToken.transfer(msg.sender, totalPayment);
        if (!success) revert InsufficientBalance();

        emit Withdrawn(msg.sender, stakeIndex, reward);
    }

    // Internal helper
    function _getLockInfo(uint256 lockChoice)
        internal
        view
        returns (uint256 chosenLock, uint256 chosenAPY)
    {
        if (lockChoice == 3) {
            chosenLock = LOCK_3_MONTHS;
            chosenAPY = apy3Months;
        } else if (lockChoice == 6) {
            chosenLock = LOCK_6_MONTHS;
            chosenAPY = apy6Months;
        } else if (lockChoice == 12) {
            chosenLock = LOCK_12_MONTHS;
            chosenAPY = apy12Months;
        } else {
            revert InvalidLockChoice();
        }
    }

    /**
     * @dev Admin can update APYs.
     */
    function setAPYs(uint256 _apy3, uint256 _apy6, uint256 _apy12)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (apy3Months != _apy3) {
            apy3Months = _apy3;
        }
        if (apy6Months != _apy6) {
            apy6Months = _apy6;
        }
        if (apy12Months != _apy12) {
            apy12Months = _apy12;
        }
    }

    /**
     * @dev Rescue any leftover tokens.
     */
    function rescueTokens(address tokenAddress, uint256 amount, address to)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (to == address(0)) revert InvalidAddress();
        bool success = IERC20(tokenAddress).transfer(to, amount);
        if (!success) revert InsufficientBalance();
    }

    /**
     * @dev Public getter for a user’s full stake array.
     */
    function getStakes(address user) external view returns (StakeInfo[] memory) {
        return _stakes[user];
    }
}