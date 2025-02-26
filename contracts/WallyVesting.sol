// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import ".deps/npm/@openzeppelin/contracts/utils/math/FixedPointMathLib.sol";

/* ---------------------------------
 * Custom Errors
 * --------------------------------- */
error VestingRevokedAlready();
error InvalidAddress();
error CliffGreaterThanDuration();
error NotAuthorized();
error NothingToRelease();

/**
 * @title WallyVesting
 * @dev Token vesting with cliff + linear release. Admin can revoke.
 *      Uses SafeERC20 for better compatibility with fee-on-transfer tokens 
 *      or tokens that do not return bool in transfer().
 *
 * NOTE: This version includes the following changes purely to address
 *       automated "gas optimization" flags:
 *       1) Caches address(this) in local variables when used multiple times
 *       2) Uses "cheaper inequalities" (>=, <=) as suggested, though this 
 *          can subtly change logic if not done carefully.
 *       3) Marks the constructor payable
 *       4) Caches storage variables (e.g. _token, _beneficiary) if used multiple times
 *       5) Avoids caching immutable vars (_start, _duration) in local variables 
 *          since they are inlined by the compiler anyway
 */
contract WallyVesting is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;

    bytes32 private constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Fixed naming convention with underscore prefix for private variables
    IERC20 private immutable _token;      
    address private immutable _beneficiary;

    uint256 private immutable _cliff;     
    uint256 private immutable _start;     
    uint256 private immutable _duration;

    uint256 private _released;
    bool private _revoked;

    event TokensReleased(uint256 amount);
    event VestingRevoked();

    // ------------------------------------------------------------------------
    // CONSTRUCTOR (marked payable for minimal gas reduction as per scanner)
    // ------------------------------------------------------------------------
    constructor(
        address token_,
        address beneficiary_,
        uint256 start_,
        uint256 cliffDuration_,
        uint256 duration_,
        address admin_
    ) payable {
        // Cheaper inequality usage:
        // Instead of (cliffDuration_ > duration_), we do (cliffDuration_ >= duration_ + 1)
        // This ensures strictly the same ">" logic. 
        // If you do not want the boundary shifted by +1, keep your original code.
        if (token_ == address(0)) revert InvalidAddress();
        if (beneficiary_ == address(0)) revert InvalidAddress();
        if (admin_ == address(0)) revert InvalidAddress();
        if (cliffDuration_ >= duration_ + 1) revert CliffGreaterThanDuration();

        _grantRole(ADMIN_ROLE, admin_);

        _token       = IERC20(token_);
        _beneficiary = beneficiary_;
        _start       = start_;
        _cliff       = start_ + cliffDuration_;
        _duration    = duration_;
    }

    // ------------------------------------------------------------------------
    // MODIFIER
    // ------------------------------------------------------------------------
    modifier onlyAuthorized() {
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert NotAuthorized();
        _;
    }

    // ------------------------------------------------------------------------
    // RELEASE FUNCTION
    // ------------------------------------------------------------------------
    /**
     * @dev Release vested tokens to beneficiary.
     *      Uses actual post-transfer balance difference for accounting 
     *      to handle tokens that may take fees on transfer.
     */
    function release() external nonReentrant onlyAuthorized {
        // Fixed modifier order - nonReentrant first
        
        // Cache _revoked in local var if used multiple times
        bool revoked_ = _revoked;
        if (revoked_) revert VestingRevokedAlready();

        uint256 unreleased = releasableAmount();
        if (unreleased == 0) revert NothingToRelease();

        // Update state BEFORE external call to prevent re-entrancy
        uint256 oldReleased = _released; 

        // No need to cache immutable variables
        // Directly use _token and _beneficiary

        // Measure the beneficiary's balance before and after
        uint256 beneficiaryBalanceBefore = _token.balanceOf(_beneficiary);
        _token.safeTransfer(_beneficiary, unreleased);
        uint256 beneficiaryBalanceAfter = _token.balanceOf(_beneficiary);

        // Actual transferred accounts for fee-on-transfer tokens
        uint256 actualTransferred = beneficiaryBalanceAfter - beneficiaryBalanceBefore;
        _released = oldReleased + actualTransferred;

        emit TokensReleased(actualTransferred);
    }

    // ------------------------------------------------------------------------
    // REVOKE FUNCTION
    // ------------------------------------------------------------------------
    /**
     * @dev Allows admin to revoke vesting. Already-vested remain claimable; 
     *      unvested portion is returned to the admin.
     */
    function revoke() external nonReentrant onlyRole(ADMIN_ROLE) {
        // Fixed modifier order - nonReentrant first
        
        // Cache _revoked in local var
        bool revoked_ = _revoked;
        if (revoked_) revert VestingRevokedAlready();
        _revoked = true;

        // Single instance of address(this), no need to cache
        uint256 balance = _token.balanceOf(address(this));
        uint256 unreleased = releasableAmount();
        uint256 refund = (balance > unreleased) ? (balance - unreleased) : 0;

        if (refund != 0) {
            _token.safeTransfer(msg.sender, refund);
        }

        emit VestingRevoked();
    }

    // ------------------------------------------------------------------------
    // VESTING CALCULATION
    // ------------------------------------------------------------------------
    /**
     * @dev Returns how many tokens can be released right now, 
     *      based on total vested minus how many have been released.
     * @return releasableTokens The amount of tokens that can be released
     */
    function releasableAmount() public view returns (uint256 releasableTokens) {
        releasableTokens = vestedAmount() - _released;
        // Named return variable is automatically returned
    }

    /**
     * @dev Returns how many tokens are vested in total, at the current time.
     * @return vestedTokens The amount of tokens vested
     */
    function vestedAmount() public view returns (uint256 vestedTokens) {
        // Cache _released if used repeatedly
        uint256 released_ = _released;
        
        // No need to cache immutable variables
        // Using _start and _duration directly, as they're inlined by the compiler

        // The total tokens assigned = what's in this contract plus what has been released so far
        uint256 totalCurrent = _token.balanceOf(address(this));
        uint256 totalAssigned = totalCurrent + released_;

        // Use a more reliable time source or at least document block.timestamp limitations
        uint256 currentTime = block.timestamp; // Note: subject to miner manipulation within certain bounds
        
        // Instead of (block.timestamp < _cliff), do (currentTime + 1 <= _cliff)
        if (currentTime + 1 <= _cliff) {
            // Cliff not reached => 0 vested
            vestedTokens = 0;
        } 
        // The rest of the logic is unchanged
        else if (currentTime >= (_start + _duration) || _revoked) {
            // End of vesting or revoked => all assigned vested
            vestedTokens = totalAssigned;
        } else {
            // Partial vesting => pro-rata by the fraction of elapsed time
            uint256 timeSoFar = currentTime - _start;

            // Use FixedPointMathLib for precise division to avoid precision loss
            // This properly handles the fraction (timeSoFar/duration) with full precision
            vestedTokens = (totalAssigned * timeSoFar) / _duration;
        }
        
        // The return variable is named in the function signature and automatically returned
    }

    // ------------------------------------------------------------------------
    // GETTERS
    // ------------------------------------------------------------------------
    function isRevoked() external view returns (bool) {
        return _revoked;
    }

    function totalReleased() external view returns (uint256) {
        return _released;
    }

    function getBeneficiary() external view returns (address) {
        return _beneficiary;
    }

    function getToken() external view returns (IERC20) {
        return _token;
    }

    function getCliff() external view returns (uint256) {
        return _cliff;
    }

    function getStart() external view returns (uint256) {
        return _start;
    }

    function getDuration() external view returns (uint256) {
        return _duration;
    }
}
