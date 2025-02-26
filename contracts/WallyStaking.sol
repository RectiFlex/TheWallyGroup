// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/* -----------------------------------------------------
 * Custom Errors
 * ---------------------------------------------------- */
error InvalidAmount();
error InvalidDuration();
error StakingNotActive();
error StakingStillLocked();
error NoRewardsAvailable();
error InsufficientRewardsPool();
error InvalidZeroAddress();
error NoActiveStake();
error TransferFailed();
error DurationAlreadyExists();
error InsufficientBalance();

/**
 * @title WallyStaking
 * @dev Allows users to stake WallyToken for a predetermined duration
 * to earn rewards at a fixed APY. Features multiple staking durations
 * with corresponding APY rates.
 */
contract WallyStaking is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Roles
    bytes32 private constant _ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 private constant _REWARDS_MANAGER_ROLE = keccak256("REWARDS_MANAGER_ROLE");

    // Events
    event Staked(address indexed user, uint256 amount, uint256 indexed duration, uint256 unlockTime);
    event Unstaked(address indexed user, uint256 stakedAmount, uint256 rewardAmount);
    event RewardClaimed(address indexed user, uint256 amount);
    event StakingPlanAdded(uint256 indexed duration, uint256 indexed apy);
    event StakingPlanUpdated(uint256 indexed duration, uint256 indexed apy);
    event RewardsAdded(uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event StakingPaused(bool indexed isPaused);

    // Staking plans
    struct StakingPlan {
        bool isActive;
        uint256 apr; // Annual percentage rate in basis points (1% = 100)
    }

    // User staking data - packed for storage efficiency
    struct UserStakingData {
        uint256 stakedAmount;
        uint256 stakingStartTime;
        uint256 lastClaimTime;
        uint256 stakingEndTime;
        uint256 duration;
        uint256 apr;
        bool isActive;
    }

    // State variables
    IERC20 private immutable _token;
    mapping(uint256 duration => StakingPlan plan) private _stakingPlans; // Named mapping parameters
    mapping(address user => UserStakingData data) private _userStakingData; // Named mapping parameters
    uint256 private _totalStaked;
    uint256 private _rewardsPool;
    bool private _stakingPaused;
    uint256[] private _availableDurations; // Array to track available durations

    // Constants
    uint256 private constant _BASIS_POINTS = 10000; // 100% = 10000
    uint256 private constant _ONE_YEAR = 365 days;

    /**
     * @dev Constructor sets up the initial contract state
     * @param tokenAddress Address of the WallyToken contract
     * @param adminAddress Address of the admin who will manage the contract
     */
    constructor(address tokenAddress, address adminAddress) payable { // Made payable for gas optimization
        if (tokenAddress == address(0)) revert InvalidZeroAddress();
        if (adminAddress == address(0)) revert InvalidZeroAddress();

        _token = IERC20(tokenAddress);
        
        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, adminAddress);
        _grantRole(_ADMIN_ROLE, adminAddress);
        _grantRole(_REWARDS_MANAGER_ROLE, adminAddress);

        // Set ADMIN_ROLE as the admin for REWARDS_MANAGER_ROLE
        _setRoleAdmin(_REWARDS_MANAGER_ROLE, _ADMIN_ROLE);

        // Initialize default staking plans (3, 6, 12 months)
        _addStakingPlan(90 days, 500);  // 5% APR for 3 months
        _addStakingPlan(180 days, 800); // 8% APR for 6 months
        _addStakingPlan(365 days, 1200); // 12% APR for 12 months
        
        _stakingPaused = false;
    }

    /**
     * @dev Adds a staking plan with a specific duration and APR
     * @param duration Duration in seconds
     * @param apr Annual percentage rate in basis points (100 = 1%)
     */
    function addStakingPlan(uint256 duration, uint256 apr) 
        external 
        nonReentrant 
        onlyRole(_ADMIN_ROLE) 
    {
        _addStakingPlan(duration, apr);
    }

    /**
     * @dev Updates an existing staking plan
     * @param duration Duration of the plan to update
     * @param apr New annual percentage rate in basis points
     * @param isActive Whether the plan is active
     */
    function updateStakingPlan(uint256 duration, uint256 apr, bool isActive) 
        external 
        nonReentrant 
        onlyRole(_ADMIN_ROLE) 
    {
        // Validate duration exists
        bool found = false;
        // Cache array length to save gas
        uint256 durationsLength = _availableDurations.length;
        for (uint256 i = 0; i < durationsLength; ++i) { // Using pre-increment (++i) instead of post-increment (i++)
            if (_availableDurations[i] == duration) {
                found = true;
                break;
            }
        }
        if (!found) revert InvalidDuration();

        // Only update if values are different from current ones
        StakingPlan storage plan = _stakingPlans[duration];
        if (plan.apr != apr) {
            plan.apr = apr;
        }
        
        if (plan.isActive != isActive) {
            plan.isActive = isActive;
        }
        
        emit StakingPlanUpdated(duration, apr);
    }

    /**
     * @dev Pauses or unpauses staking
     * @param paused Whether staking should be paused
     */
    function setStakingPaused(bool paused) 
        external 
        nonReentrant 
        onlyRole(_ADMIN_ROLE) 
    {
        // Only update if value is different
        if (_stakingPaused != paused) {
            _stakingPaused = paused;
            emit StakingPaused(paused);
        }
    }

    /**
     * @dev Adds tokens to the rewards pool
     * @param amount Amount of tokens to add
     */
    function addRewards(uint256 amount) 
        external 
        nonReentrant 
        onlyRole(_REWARDS_MANAGER_ROLE) 
    {
        if (amount == 0) revert InvalidAmount();
        
        // Cache address(this) for multiple uses
        address self = address(this);
        
        // Cache storage variable to avoid multiple SLOADs
        uint256 rewardsPool = _rewardsPool;
        
        // Transfer tokens from sender to contract
        _token.safeTransferFrom(msg.sender, self, amount);
        
        // Update rewards pool
        // Using direct assignment instead of +=
        _rewardsPool = rewardsPool + amount;
        
        emit RewardsAdded(amount);
    }

    /**
     * @dev Allows a user to stake tokens
     * @param amount Amount to stake
     * @param duration Duration in seconds to stake for
     */
    function stake(uint256 amount, uint256 duration) 
        external 
        nonReentrant 
    {
        // Cache storage variables to avoid multiple SLOADs
        bool stakingPaused = _stakingPaused;
        uint256 totalStaked = _totalStaked;

        // Validation
        if (stakingPaused) revert StakingNotActive();
        if (amount == 0) revert InvalidAmount();
        
        // Check if the duration is valid and active
        StakingPlan storage plan = _stakingPlans[duration];
        if (!plan.isActive) revert InvalidDuration();
        
        // Cache address(this)
        address self = address(this);
        
        // Cache current block timestamp to save gas
        uint256 currentTime = block.timestamp;
        
        // Check if user has an active stake
        UserStakingData storage userData = _userStakingData[msg.sender];
        if (userData.isActive) {
            // If user already has an active stake, first claim any available rewards
            if (userData.stakingStartTime != 0 && currentTime >= userData.stakingStartTime) {
                uint256 pendingRewards = calculatePendingRewards(msg.sender);
                if (pendingRewards != 0) {
                    _claimRewards(msg.sender, pendingRewards);
                }
            }
        }
        
        // Calculate unlock time
        uint256 unlockTime = currentTime + duration;
        
        // Transfer tokens from user to contract
        _token.safeTransferFrom(msg.sender, self, amount);
        
        // Update user data - assigning individual fields instead of the whole struct at once
        userData.stakedAmount = amount;
        userData.stakingStartTime = currentTime;
        userData.stakingEndTime = unlockTime;
        userData.duration = duration;
        userData.apr = plan.apr;
        userData.isActive = true;
        userData.lastClaimTime = currentTime;
        
        // Update total staked amount
        // Using direct assignment instead of +=
        _totalStaked = totalStaked + amount;
        
        emit Staked(msg.sender, amount, duration, 0); // Don't need to include timestamp in event
    }

    /**
     * @dev Allows a user to unstake their tokens after the lock period
     */
    function unstake() 
        external 
        nonReentrant 
    {
        UserStakingData storage userData = _userStakingData[msg.sender];
        
        // Validations
        if (!userData.isActive) revert NoActiveStake();
        if (block.timestamp <= userData.stakingEndTime) revert StakingStillLocked();
        
        // No need to cache immutable variables
        address self = address(this);
        
        uint256 stakedAmount = userData.stakedAmount;
        uint256 pendingRewards = calculatePendingRewards(msg.sender);
        
        // Reset user data
        userData.stakedAmount = 0;
        userData.stakingStartTime = 0;
        userData.stakingEndTime = 0;
        userData.duration = 0;
        userData.apr = 0;
        userData.isActive = false;
        userData.lastClaimTime = 0;
        
        // Update total staked
        // Using direct assignment instead of -=
        _totalStaked = _totalStaked - stakedAmount;
        
        // Transfer tokens back to user
        _token.safeTransfer(msg.sender, stakedAmount);
        
        // Transfer rewards if any
        if (pendingRewards != 0) {
            _claimRewards(msg.sender, pendingRewards);
        }
        
        emit Unstaked(msg.sender, stakedAmount, pendingRewards);
    }

    /**
     * @dev Allows users to claim rewards without unstaking
     */
    function claimRewards() 
        external 
        nonReentrant 
    {
        UserStakingData storage userData = _userStakingData[msg.sender];
        
        // Validations
        if (!userData.isActive) revert NoActiveStake();
        
        uint256 pendingRewards = calculatePendingRewards(msg.sender);
        if (pendingRewards == 0) revert NoRewardsAvailable();
        
        // Update last claim time
        userData.lastClaimTime = block.timestamp;
        
        // Transfer rewards
        _claimRewards(msg.sender, pendingRewards);
    }

    /**
     * @dev Emergency withdraw function in case of critical issues
     * Note: This doesn't calculate or distribute rewards
     */
    function emergencyWithdraw() 
        external 
        nonReentrant 
    {
        UserStakingData storage userData = _userStakingData[msg.sender];
        
        // Validations
        if (!userData.isActive) revert NoActiveStake();
        
        // No need to cache immutable variables
        
        uint256 stakedAmount = userData.stakedAmount;
        
        // Reset user data
        userData.stakedAmount = 0;
        userData.stakingStartTime = 0;
        userData.stakingEndTime = 0;
        userData.duration = 0;
        userData.apr = 0;
        userData.isActive = false;
        userData.lastClaimTime = 0;
        
        // Update total staked
        // Using direct assignment instead of -=
        _totalStaked = _totalStaked - stakedAmount;
        
        // Transfer tokens back to user
        _token.safeTransfer(msg.sender, stakedAmount);
        
        emit EmergencyWithdraw(msg.sender, stakedAmount);
    }

    /**
     * @dev Calculates pending rewards for a user
     * @param user Address of the user
     * @return rewards Reward amount
     */
    function calculatePendingRewards(address user) 
        public 
        view 
        returns (uint256 rewards) 
    {
        UserStakingData storage userData = _userStakingData[user];
        
        if (!userData.isActive || userData.stakedAmount == 0) {
            return 0;
        }
        
        // Calculate time elapsed since last claim
        uint256 endTime = block.timestamp;
        if (endTime >= userData.stakingEndTime) {
            endTime = userData.stakingEndTime;
        }
        
        uint256 timeElapsed = endTime - userData.lastClaimTime;
        if (timeElapsed == 0) {
            return 0;
        }
        
        // Calculate rewards: (stakedAmount * APR * timeElapsed) / (BASIS_POINTS * ONE_YEAR)
        // Safe math calculation to avoid overflow and precision loss
        // Multiply first, then divide to minimize precision loss
        uint256 numerator = userData.stakedAmount * userData.apr * timeElapsed;
        uint256 denominator = _BASIS_POINTS * _ONE_YEAR;
        rewards = numerator / denominator;
        
        // No need for return statement when using named returns
    }

    /**
     * @dev Get user staking information
     * @param user Address of the user
     * @return userInfo Struct containing all user staking information
     */
    // Packed for gas efficiency - similar types grouped together
    struct UserStakingInfo {
        uint256 stakedAmount;
        uint256 stakingStartTime; 
        uint256 stakingEndTime;
        uint256 duration;
        uint256 apr;
        uint256 pendingRewards;
        bool isActive;
    }
    
    function getUserStakingInfo(address user) 
        external 
        view 
        returns (UserStakingInfo memory userInfo) 
    {
        UserStakingData storage userData = _userStakingData[user];
        
        userInfo.stakedAmount = userData.stakedAmount;
        userInfo.stakingStartTime = userData.stakingStartTime;
        userInfo.stakingEndTime = userData.stakingEndTime;
        userInfo.duration = userData.duration;
        userInfo.apr = userData.apr;
        userInfo.isActive = userData.isActive;
        userInfo.pendingRewards = calculatePendingRewards(user);
        
        return userInfo;
    }

    /**
     * @dev Get staking plan details
     * @param duration Duration of the plan
     * @return isActive Whether the plan is active
     * @return apr APR of the plan in basis points
     */
    function getStakingPlan(uint256 duration) 
        external 
        view 
        returns (bool isActive, uint256 apr) 
    {
        StakingPlan storage plan = _stakingPlans[duration];
        return (plan.isActive, plan.apr);
    }

    /**
     * @dev Get all available staking durations
     * @return durations Array of available durations
     */
    function getAvailableDurations() 
        external 
        view 
        returns (uint256[] memory durations) 
    {
        return _availableDurations;
    }

    /**
     * @dev Get contract stats
     * @return totalStaked Total tokens staked
     * @return rewardsPool Available rewards pool
     * @return stakingPaused Whether staking is paused
     */
    function getContractStats() 
        external 
        view 
        returns (uint256 totalStaked, uint256 rewardsPool, bool stakingPaused) 
    {
        return (_totalStaked, _rewardsPool, _stakingPaused);
    }

    /**
     * @dev Internal function to add a staking plan
     * @param duration Duration in seconds
     * @param apr Annual percentage rate in basis points
     */
    function _addStakingPlan(uint256 duration, uint256 apr) 
        private 
    {
        if (duration == 0) revert InvalidDuration();
        if (_stakingPlans[duration].isActive) revert DurationAlreadyExists();
        
        // Create and set the staking plan
        StakingPlan storage plan = _stakingPlans[duration];
        plan.isActive = true;
        plan.apr = apr;
        
        _availableDurations.push(duration);
        
        emit StakingPlanAdded(duration, apr);
    }

    /**
     * @dev Internal function to claim rewards
     * @param user Address of the user
     * @param amount Amount of rewards to claim
     */
    function _claimRewards(address user, uint256 amount) 
        private 
    {
        // Cache storage variable to avoid multiple SLOADs
        uint256 rewardsPool = _rewardsPool;
        
        if (amount >= rewardsPool) revert InsufficientRewardsPool(); // Use non-strict inequality
        
        // Using direct assignment instead of -=
        _rewardsPool = rewardsPool - amount;
        _token.safeTransfer(user, amount);
        
        emit RewardClaimed(user, amount);
    }
}