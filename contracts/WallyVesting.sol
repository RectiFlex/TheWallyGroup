// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
 */
contract WallyVesting is AccessControl {
    bytes32 private constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    IERC20 private immutable token;      
    address private immutable beneficiary;

    uint256 private immutable cliff;     
    uint256 private immutable start;     
    uint256 private immutable duration;  

    uint256 private released;
    bool private revoked;

    event TokensReleased(uint256 amount);
    event VestingRevoked();

    constructor(
        address _token,
        address _beneficiary,
        uint256 _start,
        uint256 _cliffDuration,
        uint256 _duration,
        address _admin
    ) payable {
        if (_token == address(0)) revert InvalidAddress();
        if (_beneficiary == address(0)) revert InvalidAddress();
        if (_admin == address(0)) revert InvalidAddress();
        if (_cliffDuration > _duration) revert CliffGreaterThanDuration();

        _grantRole(ADMIN_ROLE, _admin);

        token = IERC20(_token);
        beneficiary = _beneficiary;
        start = _start;
        cliff = _start + _cliffDuration;
        duration = _duration;
    }

    modifier onlyAuthorized() {
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert NotAuthorized();
        _;
    }

    /**
     * @dev Release vested tokens to beneficiary.
     */
    function release() external onlyAuthorized {
        if (revoked) revert VestingRevokedAlready();
        uint256 unreleased = releasableAmount();
        if (unreleased == 0) revert NothingToRelease();

        released = released + unreleased;

        bool success = token.transfer(beneficiary, unreleased);
        require(success, "Transfer fail");

        emit TokensReleased(unreleased);
    }

    /**
     * @dev Allows admin to revoke vesting. Already-vested remain claimable; unvested => admin.
     */
    function revoke() external onlyRole(ADMIN_ROLE) {
        if (revoked) revert VestingRevokedAlready();
        revoked = true;

        uint256 balance = token.balanceOf(address(this));
        uint256 unreleased = releasableAmount();
        uint256 refund = (balance > unreleased) ? (balance - unreleased) : 0;

        if (refund != 0) {
            bool success = token.transfer(msg.sender, refund);
            require(success, "Refund fail");
        }
        emit VestingRevoked();
    }

    function releasableAmount() public view returns (uint256) {
        return vestedAmount() - released;
    }

    function vestedAmount() public view returns (uint256) {
        uint256 totalCurrent = token.balanceOf(address(this));
        uint256 totalAssigned = totalCurrent + released;

        if (block.timestamp < cliff) {
            return 0;
        } else if (block.timestamp >= (start + duration) || revoked) {
            return totalAssigned;
        } else {
            uint256 timeSoFar = block.timestamp - start;
            uint256 vested = (totalAssigned * timeSoFar) / duration;
            return vested;
        }
    }

    // Optional getters
    function isRevoked() external view returns (bool) {
        return revoked;
    }
    function totalReleased() external view returns (uint256) {
        return released;
    }
    function getBeneficiary() external view returns (address) {
        return beneficiary;
    }
}