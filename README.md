Wally Token Ecosystem

Welcome to the Wally token repository!
Here you’ll find all the Solidity smart contracts and supporting code for the Wally DeFi ecosystem, including:
	•	WallyToken – Your primary ERC20 token with advanced anti-bot and sniping protection.
	•	WallyStaking – A time-locked staking system with dynamic APYs.
	•	WallyVesting – Linear vesting for team/foundation tokens with cliff and optional revocation.
	•	WallyAirdrop – A simple airdrop contract for batch token distributions.

	Note: Always audit and test thoroughly before deploying to mainnet.

Table of Contents
	•	Overview
	•	Contracts
	•	WallyToken
	•	WallyStaking
	•	WallyVesting
	•	WallyAirdrop
	•	Development
	•	Installation
	•	Compilation
	•	Testing
	•	Deployment
	•	Security & Audits
	•	License
	•	Disclaimer

Overview

The Wally ecosystem is designed to bring together DeFi capabilities and community-driven initiatives. Here’s a quick rundown:
	•	Zero-Tax ERC20 token with advanced features.
	•	DAO Governance integration using AccessControl.
	•	Anti-Bot Tools: trading toggle, cooldowns, blacklisting, sniper protection.
	•	Time-Locked Staking for sustainable rewards.
	•	Linear Vesting for controlled token distribution.
	•	Batch Airdrops for community events or marketing campaigns.

Feel free to explore, customize, and build upon these contracts to fit your project’s unique needs!

Contracts

1. WallyToken ♻️

A zero-tax ERC20 token with:
	•	DAO Ownership or multi-sig control via ADMIN_ROLE.
	•	Anti-Bot Tools:
	•	Trading toggle (enables/disables public transfers).
	•	Blacklist for malicious actors.
	•	Max transaction limit for early-phase controls.
	•	Optional cooldown period between user transfers.
	•	Time-based (or block-based) sniper protection.
	•	Minting/Burning restricted by MINTER_ROLE and BURNER_ROLE.
	•	Rescue Functions to recover stuck ERC20 tokens or ETH.

// Pseudocode snippet
contract WallyToken is ERC20, AccessControl {
    constructor(address _router) ERC20("Wally Token", "TWG") {
        // ...
    }
    function setTradingEnabled(bool _enabled) external onlyRole(ADMIN_ROLE) { ... }
    // ...
}

2. WallyStaking 💰

A staking system designed to reward users who lock up their Wally tokens. Features:
	•	Multiple Lock Durations (3, 6, or 12 months).
	•	Simple APY Calculation: Earn more by locking longer!
	•	Admin Control to set APYs, rescue leftover tokens, etc.
	•	Time-Locked Withdrawals ensuring fairness.

Stakers deposit WallyToken into WallyStaking, then later withdraw principal + rewards.

3. WallyVesting ⏰

For distributing tokens over a defined schedule:
	•	Linear Vesting: Tokens release continuously from start to start + duration.
	•	Cliff: No tokens released before the cliff.
	•	Revocable by Admin: Unvested tokens can be reclaimed if necessary.
	•	One Beneficiary per Contract or use a factory for multiple.

Perfect for team allocations, partner distributions, and reducing sell pressure!

4. WallyAirdrop 🎁

A simple batch distribution contract to spread Wally tokens:
	•	Prefunded by the admin.
	•	Single Transaction to airdrop tokens to a list of recipients.
	•	Rescue function for leftover tokens.

Ideal for marketing campaigns, community giveaways, or promotional events.

Development

Installation
	1.	Clone the repository:

git clone https://github.com/YOUR_ORG/wally-token.git
cd wally-token


	2.	Install dependencies (e.g., Foundry or Hardhat):

# Using Foundry
forge install

# Or using NPM for Hardhat
npm install


	3.	Configure hardhat.config.js or foundry.toml as needed.

Compilation
	•	Hardhat:

npx hardhat compile


	•	Foundry:

forge build



Testing
	•	Hardhat (JavaScript tests):

npx hardhat test


	•	Foundry (Solidity tests):

forge test



Explore the test/ directory for examples covering each contract. Ensure you have a local node or test environment running if needed.

Deployment
	1.	Deploy WallyToken by passing the Uniswap Router address in the constructor.
	2.	Grant Roles (ADMIN_ROLE, MINTER_ROLE, BURNER_ROLE) to your DAO or multi-sig.
	3.	(Optional) Deploy WallyStaking and fund it with enough tokens to cover rewards.
	4.	(Optional) Deploy WallyVesting for each beneficiary/team member. Transfer allocated tokens to each vesting contract.
	5.	(Optional) Deploy WallyAirdrop, pre-fund it, and distribute tokens to your community.

Always verify your addresses and calls on a testnet (e.g., Goerli, Sepolia) before mainnet deployment.

Security & Audits 🔒
	•	Third-Party Audits are highly recommended for all production code.
	•	Role Management: Be mindful of powerful roles like ADMIN_ROLE – keep them on a multi-sig or DAO governance.
	•	Anti-Bot features: Thoroughly test your trading toggle, cooldowns, blacklisting, and sniper checks to ensure a smooth launch.

License

All contracts are released under the MIT License. See LICENSE for details.

Disclaimer

No warranties or guarantees are given regarding their security or correctness.
Always perform audits, review the code, and test extensively before mainnet deployment.

Happy coding & enjoy building with Wally! 💻✨
