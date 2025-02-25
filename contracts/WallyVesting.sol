// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title WallyVesting
 * @dev Token vesting with cliff + linear release. Admin (DAO) can revoke.
 *
 * - If revoked, vested tokens remain claimable; unvested tokens return to admin.
 * - The beneficiary calls `release()` to get vested tokens.
 */
contract WallyVesting is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    IERC20 public immutable token;      // The Wally token
    address public immutable beneficiary;

    uint256 public immutable cliff;     // cliff time
    uint256 public immutable start;     // start time
    uint256 public immutable duration;  // total vesting duration

    uint256 public released;
    bool public revoked;

    event TokensReleased(uint256 amount);
    event VestingRevoked();

    constructor(
        address _token,
        address _beneficiary,
        uint256 _start,
        uint256 _cliffDuration,
        uint256 _duration,
        address _admin
    ) {
        require(_token != address(0), "Invalid token");
        require(_beneficiary != address(0), "Invalid beneficiary");
        require(_admin != address(0), "Invalid admin");
        require(_cliffDuration <= _duration, "Cliff > duration");

        _grantRole(ADMIN_ROLE, _admin);

        token = IERC20(_token);
        beneficiary = _beneficiary;
        start = _start;
        cliff = _start + _cliffDuration;
        duration = _duration;
    }

    /**
     * @dev Release vested tokens to beneficiary.
     */
    function release() external {
        require(!revoked, "Vesting revoked");
        uint256 unreleased = releasableAmount();
        require(unreleased > 0, "Nothing to release");

        released += unreleased;
        token.transfer(beneficiary, unreleased);

        emit TokensReleased(unreleased);
    }

    /**
     * @dev Allows admin to revoke vesting. Already-vested remain claimable; unvested returned to admin.
     */
    function revoke() external onlyRole(ADMIN_ROLE) {
        require(!revoked, "Already revoked");
        revoked = true;

        uint256 balance = token.balanceOf(address(this));
        uint256 unreleased = releasableAmount();
        uint256 refund = balance - unreleased;

        if (refund > 0) {
            token.transfer(msg.sender, refund);
        }
        emit VestingRevoked();
    }

    /**
     * @dev Calculates how many tokens can be released right now.
     */
    function releasableAmount() public view returns (uint256) {
        return vestedAmount() - released;
    }

    /**
     * @dev Calculates total vested tokens at the current time.
     */
    function vestedAmount() public view returns (uint256) {
        uint256 totalCurrent = token.balanceOf(address(this));
        uint256 total = totalCurrent + released;

        if (block.timestamp < cliff) {
            return 0;
        } else if (block.timestamp >= (start + duration) || revoked) {
            return total;
        } else {
            // Linear vesting from start -> start + duration
            uint256 vested = (total * (block.timestamp - start)) / duration;
            return vested;
        }
    }
}