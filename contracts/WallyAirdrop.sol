// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title WallyAirdrop
 * @dev Simple airdrop contract allowing batch distribution of Wally Tokens to multiple addresses.
 * 
 * Must be prefunded with enough tokens. The admin can do multiple airdrops.
 * For massive drops (thousands of addresses), consider a Merkle or claim-based approach.
 */
contract WallyAirdrop is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    IERC20 public immutable wallyToken;

    event Airdropped(address[] recipients, uint256[] amounts);
    event RescueTokens(address token, uint256 amount, address to);

    constructor(address _wallyToken, address _admin) {
        require(_wallyToken != address(0), "Invalid token");
        require(_admin != address(0), "Invalid admin");

        wallyToken = IERC20(_wallyToken);
        _grantRole(ADMIN_ROLE, _admin);
    }

    /**
     * @dev Airdrop tokens in a single batch transaction. 
     *      The contract must hold enough tokens to cover all amounts.
     *
     * @param recipients Array of addresses to receive tokens
     * @param amounts    Corresponding array of token amounts
     */
    function airdrop(address[] calldata recipients, uint256[] calldata amounts)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(recipients.length == amounts.length, "Length mismatch");
        uint256 len = recipients.length;

        for (uint256 i = 0; i < len; i++) {
            require(recipients[i] != address(0), "Zero address");
            require(
                wallyToken.balanceOf(address(this)) >= amounts[i],
                "Insufficient balance"
            );
            wallyToken.transfer(recipients[i], amounts[i]);
        }

        emit Airdropped(recipients, amounts);
    }

    /**
     * @dev Rescue any ERC20 tokens stuck in this contract, including TWG if needed.
     */
    function rescueTokens(address tokenAddress, uint256 amount, address to)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(to != address(0), "Invalid 'to'");
        IERC20(tokenAddress).transfer(to, amount);
        emit RescueTokens(tokenAddress, amount, to);
    }
}