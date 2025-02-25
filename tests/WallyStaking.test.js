const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("WallyStaking", function () {
  let WallyToken, wallyToken;
  let WallyStaking, wallyStaking;
  let admin, user1, user2, others;

  before(async () => {
    [admin, user1, user2, ...others] = await ethers.getSigners();

    // Deploy the WallyToken
    const TokenFactory = await ethers.getContractFactory("WallyToken");
    // We can reuse the mock router from previous or simply pass any valid address
    // for uniswap router since we won't test DEX logic here
    wallyToken = await TokenFactory.deploy(admin.address);
    await wallyToken.deployed();

    // The admin minted all supply to itself
  });

  beforeEach(async () => {
    // Deploy WallyStaking with admin = admin.address
    const StakingFactory = await ethers.getContractFactory("WallyStaking");
    wallyStaking = await StakingFactory.deploy(wallyToken.address, admin.address);
    await wallyStaking.deployed();
  });

  it("Should set correct roles upon deployment", async () => {
    const ADMIN_ROLE = await wallyStaking.ADMIN_ROLE();
    expect(await wallyStaking.hasRole(ADMIN_ROLE, admin.address)).to.be.true;
  });

  it("User can stake tokens for 3 months, then withdraw after time passes", async () => {
    // Transfer some tokens to user1 so they can stake
    await wallyToken.connect(admin).transfer(user1.address, 1000);

    // user1 must approve the staking contract
    await wallyToken.connect(user1).approve(wallyStaking.address, 1000);

    // user1 stakes for 3 months
    await wallyStaking.connect(user1).stake(500, 3);
    // check stake data
    const stakeInfo = await wallyStaking.stakes(user1.address, 0);
    expect(stakeInfo.amount).to.equal(500);

    // We must "simulate" 3 months pass => e.g. 90 days
    await ethers.provider.send("evm_increaseTime", [90 * 24 * 60 * 60]);
    await ethers.provider.send("evm_mine");

    // We also need to ensure the contract has enough TWG to pay rewards
    // For demonstration, let's deposit extra tokens from the admin
    await wallyToken.connect(admin).transfer(wallyStaking.address, 10000);

    // user1 withdraw
    await wallyStaking.connect(user1).withdraw(0);

    // user1 should get principal + reward
    // reward = 500 * (apy3Months/10000) * (90 days / 365 days)
    // apy3Months default = 500 (5%)
    // ~ 500 * 0.05 * (90/365) = ~6.16 TWG
    // We'll do approximate check
    const newBal = await wallyToken.balanceOf(user1.address);
    expect(newBal).to.be.gt(500); // Has to be > 500 (principal + some interest)
  });

  it("Admin can change APYs", async () => {
    const ADMIN_ROLE = await wallyStaking.ADMIN_ROLE();
    // Non-admin revert
    await expect(wallyStaking.connect(user1).setAPYs(600, 1100, 1600)).to.be.revertedWith(
      `AccessControl: account ${user1.address.toLowerCase()} is missing role ${ADMIN_ROLE}`
    );

    // Admin success
    await wallyStaking.connect(admin).setAPYs(600, 1100, 1600);
    expect(await wallyStaking.apy3Months()).to.equal(600);
    expect(await wallyStaking.apy6Months()).to.equal(1100);
    expect(await wallyStaking.apy12Months()).to.equal(1600);
  });
});