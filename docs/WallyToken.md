# Solidity API

## IUniswapV2Factory

_Interface for Uniswap V2 Factory_

### Contract
IUniswapV2Factory : contracts/WallyToken.sol

Interface for Uniswap V2 Factory

 --- 
### Functions:
### createPair

```solidity
function createPair(address tokenA, address tokenB) external returns (address pair)
```

## IUniswapV2Router02

_Interface for Uniswap V2 Router_

### Contract
IUniswapV2Router02 : contracts/WallyToken.sol

Interface for Uniswap V2 Router

 --- 
### Functions:
### factory

```solidity
function factory() external pure returns (address)
```

### WETH

```solidity
function WETH() external pure returns (address)
```

### addLiquidityETH

```solidity
function addLiquidityETH(address token, uint256 amountTokenDesired, uint256 amountTokenMin, uint256 amountETHMin, address to, uint256 deadline) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)
```

## WallyToken

- Zero-tax ERC20 token
 - **AccessControl** with a designated DAO as `ADMIN_ROLE` (not the deployer EOA)
 - **Advanced Anti-Sniping**: (launchBlock sniper checks, optional cooldown)
 - Basic anti-bot features: (trading toggle, blacklist, max tx limit)
 - Liquidity management (Uniswap V2)
 - Rescue functions for stuck tokens/ETH

_IMPORTANT: The DAO address must be a **secure** address (multi-sig or official DAO)._

### Contract
WallyToken : contracts/WallyToken.sol

IMPORTANT: The DAO address must be a **secure** address (multi-sig or official DAO).

 --- 
### Functions:
### constructor

```solidity
constructor(address _uniswapV2Router) public
```

_Constructor
 1) Mints the entire supply to the deployer (msg.sender).
 2) Sets up roles so that only the DAO address has ADMIN_ROLE.
 3) Creates a Uniswap V2 pair for (TWG / WETH).
 4) Leaves the deployer with NO admin privileges by default, fulfilling the requirement 
    that the DAO is the sole admin from the start._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _uniswapV2Router | address | Address of the Uniswap V2 router (e.g., 0x7a250d563...) |

### mint

```solidity
function mint(address to, uint256 amount) external
```

### burn

```solidity
function burn(uint256 amount) external
```

### setTradingEnabled

```solidity
function setTradingEnabled(bool _enabled) external
```

_Enables or disables trading. If enabling, records the `launchBlock` 
     for anti-sniping logic if `sniperProtectionEnabled` is true._

### setSniperProtection

```solidity
function setSniperProtection(bool _enabled, uint256 _snipeBlocks) external
```

_Turn sniper protection on or off, and set how many blocks to protect._

### setCooldownConfig

```solidity
function setCooldownConfig(bool _enabled, uint256 _cooldownTime) external
```

_Toggle cooldown enforcement and set the cooldown duration in seconds._

### setBlacklist

```solidity
function setBlacklist(address account, bool isBlacklisted) external
```

### setMaxTxAmount

```solidity
function setMaxTxAmount(uint256 _maxTxAmount) external
```

### addLiquidityETH

```solidity
function addLiquidityETH(address to, uint256 tokenAmountIn, uint256 tokenAmountMin, uint256 ethAmountMin, uint256 deadline) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)
```

_Add liquidity (TWG / ETH) on Uniswap. Must transfer `tokenAmountIn` to
     this contract first, or do it in a two-transaction flow from a front-end._

### _beforeTokenTransfer

```solidity
function _beforeTokenTransfer(address from, address to, uint256 amount) internal
```

_Hook to enforce:
 1) Trading toggle restrictions
 2) Blacklist checks
 3) Max transaction limit
 4) Sniper protection (blocks initial sniping within `snipeBlocks` of enabling)
 5) Optional per-address cooldown_

### rescueTokens

```solidity
function rescueTokens(address tokenAddress, uint256 amount, address to) external
```

### rescueETH

```solidity
function rescueETH(address payable to, uint256 amount) external
```

### receive

```solidity
receive() external payable
```

inherits ReentrancyGuard:
### _reentrancyGuardEntered

```solidity
function _reentrancyGuardEntered() internal view returns (bool)
```

_Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
`nonReentrant` function in the call stack._

inherits AccessControl:
### supportsInterface

```solidity
function supportsInterface(bytes4 interfaceId) public view virtual returns (bool)
```

_See {IERC165-supportsInterface}._

### hasRole

```solidity
function hasRole(bytes32 role, address account) public view virtual returns (bool)
```

_Returns `true` if `account` has been granted `role`._

### _checkRole

```solidity
function _checkRole(bytes32 role) internal view virtual
```

_Reverts with an {AccessControlUnauthorizedAccount} error if `_msgSender()`
is missing `role`. Overriding this function changes the behavior of the {onlyRole} modifier._

### _checkRole

```solidity
function _checkRole(bytes32 role, address account) internal view virtual
```

_Reverts with an {AccessControlUnauthorizedAccount} error if `account`
is missing `role`._

### getRoleAdmin

```solidity
function getRoleAdmin(bytes32 role) public view virtual returns (bytes32)
```

_Returns the admin role that controls `role`. See {grantRole} and
{revokeRole}.

To change a role's admin, use {_setRoleAdmin}._

### grantRole

```solidity
function grantRole(bytes32 role, address account) public virtual
```

_Grants `role` to `account`.

If `account` had not been already granted `role`, emits a {RoleGranted}
event.

Requirements:

- the caller must have ``role``'s admin role.

May emit a {RoleGranted} event._

### revokeRole

```solidity
function revokeRole(bytes32 role, address account) public virtual
```

_Revokes `role` from `account`.

If `account` had been granted `role`, emits a {RoleRevoked} event.

Requirements:

- the caller must have ``role``'s admin role.

May emit a {RoleRevoked} event._

### renounceRole

```solidity
function renounceRole(bytes32 role, address callerConfirmation) public virtual
```

_Revokes `role` from the calling account.

Roles are often managed via {grantRole} and {revokeRole}: this function's
purpose is to provide a mechanism for accounts to lose their privileges
if they are compromised (such as when a trusted device is misplaced).

If the calling account had been revoked `role`, emits a {RoleRevoked}
event.

Requirements:

- the caller must be `callerConfirmation`.

May emit a {RoleRevoked} event._

### _setRoleAdmin

```solidity
function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual
```

_Sets `adminRole` as ``role``'s admin role.

Emits a {RoleAdminChanged} event._

### _grantRole

```solidity
function _grantRole(bytes32 role, address account) internal virtual returns (bool)
```

_Attempts to grant `role` to `account` and returns a boolean indicating if `role` was granted.

Internal function without access restriction.

May emit a {RoleGranted} event._

### _revokeRole

```solidity
function _revokeRole(bytes32 role, address account) internal virtual returns (bool)
```

_Attempts to revoke `role` to `account` and returns a boolean indicating if `role` was revoked.

Internal function without access restriction.

May emit a {RoleRevoked} event._

inherits ERC165:
inherits IERC165:
inherits IAccessControl:
inherits ERC20:
### name

```solidity
function name() public view virtual returns (string)
```

_Returns the name of the token._

### symbol

```solidity
function symbol() public view virtual returns (string)
```

_Returns the symbol of the token, usually a shorter version of the
name._

### decimals

```solidity
function decimals() public view virtual returns (uint8)
```

_Returns the number of decimals used to get its user representation.
For example, if `decimals` equals `2`, a balance of `505` tokens should
be displayed to a user as `5.05` (`505 / 10 ** 2`).

Tokens usually opt for a value of 18, imitating the relationship between
Ether and Wei. This is the default value returned by this function, unless
it's overridden.

NOTE: This information is only used for _display_ purposes: it in
no way affects any of the arithmetic of the contract, including
{IERC20-balanceOf} and {IERC20-transfer}._

### totalSupply

```solidity
function totalSupply() public view virtual returns (uint256)
```

_See {IERC20-totalSupply}._

### balanceOf

```solidity
function balanceOf(address account) public view virtual returns (uint256)
```

_See {IERC20-balanceOf}._

### transfer

```solidity
function transfer(address to, uint256 value) public virtual returns (bool)
```

_See {IERC20-transfer}.

Requirements:

- `to` cannot be the zero address.
- the caller must have a balance of at least `value`._

### allowance

```solidity
function allowance(address owner, address spender) public view virtual returns (uint256)
```

_See {IERC20-allowance}._

### approve

```solidity
function approve(address spender, uint256 value) public virtual returns (bool)
```

_See {IERC20-approve}.

NOTE: If `value` is the maximum `uint256`, the allowance is not updated on
`transferFrom`. This is semantically equivalent to an infinite approval.

Requirements:

- `spender` cannot be the zero address._

### transferFrom

```solidity
function transferFrom(address from, address to, uint256 value) public virtual returns (bool)
```

_See {IERC20-transferFrom}.

Skips emitting an {Approval} event indicating an allowance update. This is not
required by the ERC. See {xref-ERC20-_approve-address-address-uint256-bool-}[_approve].

NOTE: Does not update the allowance if the current allowance
is the maximum `uint256`.

Requirements:

- `from` and `to` cannot be the zero address.
- `from` must have a balance of at least `value`.
- the caller must have allowance for ``from``'s tokens of at least
`value`._

### _transfer

```solidity
function _transfer(address from, address to, uint256 value) internal
```

_Moves a `value` amount of tokens from `from` to `to`.

This internal function is equivalent to {transfer}, and can be used to
e.g. implement automatic token fees, slashing mechanisms, etc.

Emits a {Transfer} event.

NOTE: This function is not virtual, {_update} should be overridden instead._

### _update

```solidity
function _update(address from, address to, uint256 value) internal virtual
```

_Transfers a `value` amount of tokens from `from` to `to`, or alternatively mints (or burns) if `from`
(or `to`) is the zero address. All customizations to transfers, mints, and burns should be done by overriding
this function.

Emits a {Transfer} event._

### _mint

```solidity
function _mint(address account, uint256 value) internal
```

_Creates a `value` amount of tokens and assigns them to `account`, by transferring it from address(0).
Relies on the `_update` mechanism

Emits a {Transfer} event with `from` set to the zero address.

NOTE: This function is not virtual, {_update} should be overridden instead._

### _burn

```solidity
function _burn(address account, uint256 value) internal
```

_Destroys a `value` amount of tokens from `account`, lowering the total supply.
Relies on the `_update` mechanism.

Emits a {Transfer} event with `to` set to the zero address.

NOTE: This function is not virtual, {_update} should be overridden instead_

### _approve

```solidity
function _approve(address owner, address spender, uint256 value) internal
```

_Sets `value` as the allowance of `spender` over the `owner` s tokens.

This internal function is equivalent to `approve`, and can be used to
e.g. set automatic allowances for certain subsystems, etc.

Emits an {Approval} event.

Requirements:

- `owner` cannot be the zero address.
- `spender` cannot be the zero address.

Overrides to this logic should be done to the variant with an additional `bool emitEvent` argument._

### _approve

```solidity
function _approve(address owner, address spender, uint256 value, bool emitEvent) internal virtual
```

_Variant of {_approve} with an optional flag to enable or disable the {Approval} event.

By default (when calling {_approve}) the flag is set to true. On the other hand, approval changes made by
`_spendAllowance` during the `transferFrom` operation set the flag to false. This saves gas by not emitting any
`Approval` event during `transferFrom` operations.

Anyone who wishes to continue emitting `Approval` events on the`transferFrom` operation can force the flag to
true using the following override:

```solidity
function _approve(address owner, address spender, uint256 value, bool) internal virtual override {
    super._approve(owner, spender, value, true);
}
```

Requirements are the same as {_approve}._

### _spendAllowance

```solidity
function _spendAllowance(address owner, address spender, uint256 value) internal virtual
```

_Updates `owner` s allowance for `spender` based on spent `value`.

Does not update the allowance value in case of infinite allowance.
Revert if not enough allowance is available.

Does not emit an {Approval} event._

inherits IERC20Errors:
inherits IERC20Metadata:
inherits IERC20:

 --- 
### Events:
### TradingEnabled

```solidity
event TradingEnabled(bool enabled)
```

### Blacklisted

```solidity
event Blacklisted(address account, bool isBlacklisted)
```

### MaxTxAmountUpdated

```solidity
event MaxTxAmountUpdated(uint256 newMaxTx)
```

### SniperProtectionUpdated

```solidity
event SniperProtectionUpdated(bool enabled, uint256 snipeBlocks)
```

### CooldownUpdated

```solidity
event CooldownUpdated(bool enabled, uint256 cooldownTime)
```

inherits ReentrancyGuard:
inherits AccessControl:
inherits ERC165:
inherits IERC165:
inherits IAccessControl:
### RoleAdminChanged

```solidity
event RoleAdminChanged(bytes32 role, bytes32 previousAdminRole, bytes32 newAdminRole)
```

_Emitted when `newAdminRole` is set as ``role``'s admin role, replacing `previousAdminRole`

`DEFAULT_ADMIN_ROLE` is the starting admin for all roles, despite
{RoleAdminChanged} not being emitted signaling this._

### RoleGranted

```solidity
event RoleGranted(bytes32 role, address account, address sender)
```

_Emitted when `account` is granted `role`.

`sender` is the account that originated the contract call. This account bears the admin role (for the granted role).
Expected in cases where the role was granted using the internal {AccessControl-_grantRole}._

### RoleRevoked

```solidity
event RoleRevoked(bytes32 role, address account, address sender)
```

_Emitted when `account` is revoked `role`.

`sender` is the account that originated the contract call:
  - if using `revokeRole`, it is the admin role bearer
  - if using `renounceRole`, it is the role bearer (i.e. `account`)_

inherits ERC20:
inherits IERC20Errors:
inherits IERC20Metadata:
inherits IERC20:
### Transfer

```solidity
event Transfer(address from, address to, uint256 value)
```

_Emitted when `value` tokens are moved from one account (`from`) to
another (`to`).

Note that `value` may be zero._

### Approval

```solidity
event Approval(address owner, address spender, uint256 value)
```

_Emitted when the allowance of a `spender` for an `owner` is set by
a call to {approve}. `value` is the new allowance._

