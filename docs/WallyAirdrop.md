# Solidity API

## WallyAirdrop

_Simple airdrop contract allowing batch distribution of Wally Tokens to multiple addresses.

Must be prefunded with enough tokens. The admin can do multiple airdrops.
For massive drops (thousands of addresses), consider a Merkle or claim-based approach._

### Contract
WallyAirdrop : contracts/WallyAirdrop.sol

Simple airdrop contract allowing batch distribution of Wally Tokens to multiple addresses.

Must be prefunded with enough tokens. The admin can do multiple airdrops.
For massive drops (thousands of addresses), consider a Merkle or claim-based approach.

 --- 
### Functions:
### constructor

```solidity
constructor(address _wallyToken, address _admin) public
```

### airdrop

```solidity
function airdrop(address[] recipients, uint256[] amounts) external
```

_Airdrop tokens in a single batch transaction. 
     The contract must hold enough tokens to cover all amounts._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| recipients | address[] | Array of addresses to receive tokens |
| amounts | uint256[] | Corresponding array of token amounts |

### rescueTokens

```solidity
function rescueTokens(address tokenAddress, uint256 amount, address to) external
```

_Rescue any ERC20 tokens stuck in this contract, including TWG if needed._

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

 --- 
### Events:
### Airdropped

```solidity
event Airdropped(address[] recipients, uint256[] amounts)
```

### RescueTokens

```solidity
event RescueTokens(address token, uint256 amount, address to)
```

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

