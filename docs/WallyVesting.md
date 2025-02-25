# WallyVesting

_Token vesting with cliff + linear release. Admin (DAO) can revoke.

- If revoked, vested tokens remain claimable; unvested tokens return to admin.
- The beneficiary calls `release()` to get vested tokens._

### Contract
WallyVesting : contracts/WallyVesting.sol

Token vesting with cliff + linear release. Admin (DAO) can revoke.

- If revoked, vested tokens remain claimable; unvested tokens return to admin.
- The beneficiary calls `release()` to get vested tokens.

 --- 
### Functions:
### constructor

```solidity
constructor(address _token, address _beneficiary, uint256 _start, uint256 _cliffDuration, uint256 _duration, address _admin) public
```

### release

```solidity
function release() external
```

_Release vested tokens to beneficiary._

### revoke

```solidity
function revoke() external
```

_Allows admin to revoke vesting. Already-vested remain claimable; unvested returned to admin._

### releasableAmount

```solidity
function releasableAmount() public view returns (uint256)
```

_Calculates how many tokens can be released right now._

### vestedAmount

```solidity
function vestedAmount() public view returns (uint256)
```

_Calculates total vested tokens at the current time._

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
### TokensReleased

```solidity
event TokensReleased(uint256 amount)
```

### VestingRevoked

```solidity
event VestingRevoked()
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

