// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title WallyStaking
 * @dev Users can stake Wally Tokens for fixed durations (3, 6, or 12 months) to earn rewards.
 *
 * APY-based reward: reward = principal * (apyBps/10000) * (timeStaked / 365 days)
 *
 * IMPORTANT:
 * - This contract must be funded with enough TWG to cover principal + rewards.
 * - The DAO or an admin can set APYs, rescue leftover tokens, etc.
 */
contract WallyStaking is AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Wally Token
    IERC20 public immutable wallyToken;

    // Lock durations (in seconds)
    uint256 public constant LOCK_3_MONTHS = 90 days;
    uint256 public constant LOCK_6_MONTHS = 180 days;
    uint256 public constant LOCK_12_MONTHS = 365 days;

    // APYs in basis points (e.g., 500 = 5%)
    uint256 public apy3Months = 500;    // 5%
    uint256 public apy6Months = 1000;   // 10%
    uint256 public apy12Months = 1500;  // 15%

    struct StakeInfo {
        uint256 amount;
        uint256 startTimestamp;
        uint256 lockDuration;
        uint256 apy;     // basis points
        bool withdrawn;
    }

    // user => array of stakes
    mapping(address => StakeInfo[]) public stakes;

    event Staked(address indexed user, uint256 amount, uint256 lockDuration, uint256 apy);
    event Withdrawn(address indexed user, uint256 stakeIndex, uint256 reward);

    constructor(address _wallyToken, address _admin) {
        require(_wallyToken != address(0), "Invalid token address");
        require(_admin != address(0), "Invalid admin address");

        wallyToken = IERC20(_wallyToken);
        _grantRole(ADMIN_ROLE, _admin);
    }

    /**
     * @dev Stake a specific `amount` of TWG for one of the fixed durations (3,6,12 months).
     */
    function stake(uint256 amount, uint256 lockChoice) external nonReentrant {
        require(amount > 0, "Cannot stake zero");

        // Determine lock duration / APY
        (uint256 chosenLock, uint256 chosenAPY) = _getLockInfo(lockChoice);

        // Transfer TWG from user to this contract
        bool success = wallyToken.transferFrom(msg.sender, address(this), amount);
        require(success, "Transfer failed");

        // Record stake
        stakes[msg.sender].push(
            StakeInfo({
                amount: amount,
                startTimestamp: block.timestamp,
                lockDuration: chosenLock,
                apy: chosenAPY,
                withdrawn: false
            })
        );

        emit Staked(msg.sender, amount, chosenLock, chosenAPY);
    }

    /**
     * @dev Withdraw staked tokens + reward after lock period ends.
     */
    function withdraw(uint256 stakeIndex) external nonReentrant {
        require(stakeIndex < stakes[msg.sender].length, "Invalid stake index");
        StakeInfo storage userStake = stakes[msg.sender][stakeIndex];
        require(!userStake.withdrawn, "Already withdrawn");

        uint256 unlockTime = userStake.startTimestamp + userStake.lockDuration;
        require(block.timestamp >= unlockTime, "Lock not over");

        uint256 principal = userStake.amount;
        uint256 timeStaked = userStake.lockDuration; // entire lock duration
        uint256 reward = _calculateReward(principal, userStake.apy, timeStaked);

        userStake.withdrawn = true;

        uint256 totalPayment = principal + reward;
        require(
            wallyToken.balanceOf(address(this)) >= totalPayment,
            "Insufficient reward pool"
        );

        wallyToken.transfer(msg.sender, totalPayment);

        emit Withdrawn(msg.sender, stakeIndex, reward);
    }

    /**
     * @dev Calculate simple interest rewards:
     *  reward = principal * apyBps * timeStaked / (365 days * 10000)
     */
    function _calculateReward(
        uint256 principal,
        uint256 apyBps,
        uint256 timeStaked
    ) internal pure returns (uint256) {
        return (principal * apyBps * timeStaked) / (365 days * 10000);
    }

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
            revert("Invalid lock choice");
        }
    }

    // ------------------------
    // Admin Functions
    // ------------------------

    function setAPYs(uint256 _apy3, uint256 _apy6, uint256 _apy12)
        external
        onlyRole(ADMIN_ROLE)
    {
        apy3Months = _apy3;
        apy6Months = _apy6;
        apy12Months = _apy12;
    }

    /**
     * @dev Rescue any leftover tokens. Useful if random tokens are sent by mistake.
     */
    function rescueTokens(address tokenAddress, uint256 amount, address to)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(to != address(0), "Invalid 'to'");
        IERC20(tokenAddress).transfer(to, amount);
    }
}