// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/* ---------------------------------
 * Custom Errors
 * --------------------------------- */
error InvalidParam();
error InsufficientBalance();

/**
 * @title WallyAirdrop
 * @dev Simple airdrop contract for distributing Wally Tokens in batches.
 */
contract WallyAirdrop is AccessControl {
    bytes32 private constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    IERC20 private immutable wallyToken;

    event Airdropped(address[] recipients, uint256[] amounts);
    event RescueTokens(address indexed token, uint256 amount, address indexed to);

    constructor(address _wallyToken, address _admin) payable {
        if (_wallyToken == address(0)) revert InvalidParam();
        if (_admin == address(0)) revert InvalidParam();

        wallyToken = IERC20(_wallyToken);
        _grantRole(ADMIN_ROLE, _admin);
    }

    /**
     * @dev Airdrop tokens in one transaction. Must hold enough tokens in this contract.
     */
    function airdrop(address[] calldata recipients, uint256[] calldata amounts)
        external
        onlyRole(ADMIN_ROLE)
    {
        uint256 len = recipients.length;
        if (len != amounts.length) revert InvalidParam();

        // (G011) using ++i for minor gas savings
        for (uint256 i = 0; i < len; ++i) {
            address rec = recipients[i];
            if (rec == address(0)) revert InvalidParam();

            uint256 needed = amounts[i];
            if (wallyToken.balanceOf(address(this)) < needed) revert InsufficientBalance();

            bool success = wallyToken.transfer(rec, needed);
            if (!success) revert InsufficientBalance();
        }

        emit Airdropped(recipients, amounts);
    }

    /**
     * @dev Rescue any tokens stuck in this contract.
     */
    function rescueTokens(address tokenAddress, uint256 amount, address to)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (to == address(0)) revert InvalidParam();
        bool success = IERC20(tokenAddress).transfer(to, amount);
        if (!success) revert InsufficientBalance();
        emit RescueTokens(tokenAddress, amount, to);
    }
}