Below is a corrected GitHub-compatible version of the README. The content after the WallyToken code example is no longer stuck inside a snippet. Notice how we properly close the code fence with three backticks before starting the subsequent sections.

# Wally Token Ecosystem

Welcome to the **Wally** token repository!  
Here you’ll find all the Solidity smart contracts and supporting code for the **Wally** DeFi ecosystem, including:

- **WallyToken** – Your primary ERC20 token with advanced anti-bot and sniping protection.  
- **WallyStaking** – A time-locked staking system with dynamic APYs.  
- **WallyVesting** – Linear vesting for team/foundation tokens with cliff and optional revocation.  
- **WallyAirdrop** – A simple airdrop contract for batch token distributions.

> **Note**: Always audit and test thoroughly before deploying to mainnet.  

---

## Table of Contents

- [Overview](#overview)  
- [Contracts](#contracts)  
  - [WallyToken](#1-wallytoken-)  
  - [WallyStaking](#2-wallystaking-)  
  - [WallyVesting](#3-wallyvesting-)  
  - [WallyAirdrop](#4-wallyairdrop-)  
- [Development](#development)  
  - [Installation](#installation)  
  - [Compilation](#compilation)  
  - [Testing](#testing)  
- [Deployment](#deployment)  
- [Security \& Audits](#security--audits)  
- [License](#license)  
- [Disclaimer](#disclaimer)  

---

## Overview

The **Wally** ecosystem is designed to bring together **DeFi** capabilities and **community-driven** initiatives. Here’s a quick rundown:

- **Zero-Tax ERC20** token with advanced features.  
- **DAO Governance** integration using `AccessControl`.  
- **Anti-Bot Tools**: trading toggle, cooldowns, blacklisting, sniper protection.  
- **Time-Locked Staking** for sustainable rewards.  
- **Linear Vesting** for controlled token distribution.  
- **Batch Airdrops** for community events or marketing campaigns.  

Feel free to explore, customize, and build upon these contracts to fit your project’s unique needs!  

---

## Contracts

### 1. WallyToken ♻️

A zero-tax ERC20 token with:

- **DAO or Multi-Sig Control** via `ADMIN_ROLE`.  
- **Anti-Bot Tools**: trading toggle, max transaction limit, blacklist, optional cooldown, time-based or block-based sniper protection.  
- **Minting/Burning** restricted via `MINTER_ROLE` and `BURNER_ROLE`.  
- **Rescue Functions** to recover stuck ERC20 tokens or ETH.  
- **Front-Running Mitigation** in the `approve` function (optional override).

<details>
<summary>Sample Interface</summary>

```solidity
contract WallyToken is ERC20, AccessControl {
    constructor(address _router) ERC20("Wally Token", "TWG") {
        // ...
    }
    function setTradingEnabled(bool _enabled) external onlyRole(ADMIN_ROLE) { ... }
    // ...
}

</details>
```

2. WallyStaking 💰

A staking contract with:
	•	Multiple Lock Durations (3, 6, or 12 months).
	•	Simple APY Calculation (reward = principal * APY * time).
	•	Time-Locked Withdrawals ensuring fairness and reducing volatility.
	•	Admin Control to set APYs, rescue leftover tokens, etc.

Stakers deposit WallyToken into WallyStaking and later withdraw both principal + rewards.

3. WallyVesting ⏰

For distributing tokens over time:
	•	Linear Vesting: Tokens release continuously between start and start + duration.
	•	Cliff: No tokens released before the cliff time.
	•	Revocable by an admin, returning unvested tokens back to the DAO.
	•	Per-Beneficiary Deployment: Typically one vesting contract per recipient.

Great for team allocations, partner distributions, or lockups.

4. WallyAirdrop 🎁

For batch distributing tokens:
	•	Single Transaction to a list of recipients.
	•	Prefunded with tokens by the admin.
	•	Rescue function to retrieve leftover tokens if needed.

Perfect for community rewards, event giveaways, or marketing campaigns.

Development

Installation
	1.	Clone the repository:

git clone https://github.com/YOUR_ORG/wally-token.git
cd wally-token


	2.	Install dependencies (e.g., Foundry or Hardhat):

# Using Foundry
forge install

# OR using NPM for Hardhat
npm install


	3.	Configure your hardhat.config.js, foundry.toml, or relevant config files.

Compilation
	•	Hardhat:

npx hardhat compile


	•	Foundry:

forge build

Testing
	•	Hardhat (JavaScript/TypeScript tests):

npx hardhat test


	•	Foundry (Solidity tests):

forge test



Explore the test/ directory for sample tests covering each contract.
Make sure you have a local node or test environment running if needed.

Deployment
	1.	Deploy WallyToken by passing the Uniswap Router address in the constructor.
	2.	Grant Roles (ADMIN_ROLE, MINTER_ROLE, BURNER_ROLE) to your DAO or multi-sig.
	3.	(Optional) Deploy WallyStaking and fund it with tokens to cover reward payouts.
	4.	(Optional) Deploy WallyVesting for each beneficiary/team member, then transfer allocated tokens to each vesting contract.
	5.	(Optional) Deploy WallyAirdrop and pre-fund it for batch distributions.

Always verify addresses and calls on testnets (e.g., Goerli, Sepolia) before mainnet deployment.

Security & Audits 🔒
	•	Third-Party Audits are highly recommended for all production code.
	•	Role Management: The ADMIN_ROLE has significant power (mint, burn, toggle trading, blacklist, etc.), so store this in a multi-sig or a DAO.
	•	Anti-Bot features: Thoroughly test your trading toggle, blacklisting, and cooldown logic to ensure a smooth launch.

License

All contracts are released under the MIT License. See LICENSE for details.

Disclaimer

These contracts are provided “as is.”
No warranties or guarantees are offered regarding their security or correctness.
Always audit, test, and review thoroughly before mainnet deployment.
The repository owners are not liable for any damages or losses arising from usage of this code.

Enjoy building with Wally! 🚀✨
