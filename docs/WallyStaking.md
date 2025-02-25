# Solidity API

## WallyStaking

_Users can stake Wally Tokens for fixed durations (3, 6, or 12 months) to earn rewards.

APY-based reward: reward = principal * (apyBps/10000) * (timeStaked / 365 days)

IMPORTANT:
- This contract must be funded with enough TWG to cover principal + rewards.
- The DAO or an admin can set APYs, rescue leftover tokens, etc._

### Contract
WallyStaking : contracts/WallyStaking.sol

Users can stake Wally Tokens for fixed durations (3, 6, or 12 months) to earn rewards.

APY-based reward: reward = principal * (apyBps/10000) * (timeStaked / 365 days)

IMPORTANT:
- This contract must be funded with enough TWG to cover principal + rewards.
- The DAO or an admin can set APYs, rescue leftover tokens, etc.

 --- 
### Functions:
### constructor

```solidity
constructor(address _wallyToken, address _admin) public
```

### stake

```solidity
function stake(uint256 amount, uint256 lockChoice) external
```

_Stake a specific `amount` of TWG for one of the fixed durations (3,6,12 months)._

### withdraw

```solidity
function withdraw(uint256 stakeIndex) external
```

_Withdraw staked tokens + reward after lock period ends._

### _calculateReward

```solidity
function _calculateReward(uint256 principal, uint256 apyBps, uint256 timeStaked) internal pure returns (uint256)
```

_Calculate simple interest rewards:
 reward = principal * apyBps * timeStaked / (365 days * 10000)_

### _getLockInfo

```solidity
function _getLockInfo(uint256 lockChoice) internal view returns (uint256 chosenLock, uint256 chosenAPY)
```

### setAPYs

```solidity
function setAPYs(uint256 _apy3, uint256 _apy6, uint256 _apy12) external
```

### rescueTokens

```solidity
function rescueTokens(address tokenAddress, uint256 amount, address to) external
```

_Rescue any leftover tokens. Useful if random tokens are sent by mistake._

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

 --- 
### Events:
### Staked

```solidity
event Staked(address user, uint256 amount, uint256 lockDuration, uint256 apy)
```

### Withdrawn

```solidity
event Withdrawn(address user, uint256 stakeIndex, uint256 reward)
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

