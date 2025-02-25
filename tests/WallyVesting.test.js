const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("WallyVesting", function () {
  let WallyToken, wallyToken;
  let WallyVesting, vesting;
  let admin, beneficiary, other;

  before(async () => {
    [admin, beneficiary, other] = await ethers.getSigners();

    // Deploy a simple WallyToken
    const TokenFactory = await ethers.getContractFactory("WallyToken");
    wallyToken = await TokenFactory.deploy(admin.address);
    await wallyToken.deployed();
  });

  beforeEach(async () => {
    // Let's create a vesting contract for beneficiary with a 30 day cliff, total 90 day duration
    const now = (await ethers.provider.getBlock("latest")).timestamp;
    const start = now + 10; // starts in 10s
    const cliffDuration = 30 * 24 * 60 * 60; // 30 days
    const totalDuration = 90 * 24 * 60 * 60; // 90 days

    // Deploy the vesting contract
    const VestingFactory = await ethers.getContractFactory("WallyVesting");
    vesting = await VestingFactory.deploy(
      wallyToken.address,
      beneficiary.address,
      start,
      cliffDuration,
      totalDuration,
      admin.address
    );
    await vesting.deployed();

    // Transfer tokens to vesting contract
    await wallyToken.connect(admin).transfer(vesting.address, 10000);
  });

  it("Should not allow release before cliff", async () => {
    // Time is now < start + cliff => vestedAmount is 0
    await expect(vesting.connect(beneficiary).release()).to.be.revertedWith(
      "Nothing to release"
    );
  });

  it("Should release partially after cliff, fully after duration", async () => {
    const start = await vesting.start();
    const cliff = await vesting.cliff();
    const duration = await vesting.duration();

    // Move time to just after cliff
    const jump = cliff.sub(await ethers.provider.getBlock("latest").timestamp).toNumber() + 1;
    await ethers.provider.send("evm_increaseTime", [jump]);
    await ethers.provider.send("evm_mine");

    // Some portion is vested
    await vesting.connect(beneficiary).release();
    const benBalAfter = await wallyToken.balanceOf(beneficiary.address);
    expect(benBalAfter).to.be.gt(0).and.lt(10000);

    // Move time to end of vesting
    const remain = duration.sub(jump);
    await ethers.provider.send("evm_increaseTime", [remain.toNumber() + 10]);
    await ethers.provider.send("evm_mine");

    // Now everything is vested
    await vesting.connect(beneficiary).release();
    const totalBenBal = await wallyToken.balanceOf(beneficiary.address);
    expect(totalBenBal).to.equal(10000);
  });

  it("Admin can revoke; unvested tokens are returned, vested remain claimable", async () => {
    // Move time to halfway into vesting => 50% vested
    const start = await vesting.start();
    const duration = await vesting.duration();
    const halfDuration = duration.div(2).toNumber();

    const jump = start.add(halfDuration).sub(await ethers.provider.getBlock("latest").timestamp);
    await ethers.provider.send("evm_increaseTime", [jump.toNumber()]);
    await ethers.provider.send("evm_mine");

    // About half is vested
    const vestedBeforeRevoke = await vesting.vestedAmount();

    // Revoke
    await vesting.connect(admin).revoke();

    // Now the contract's balance is just "vested portion"
    // The unvested portion was sent back to admin
    const contractBal = await wallyToken.balanceOf(vesting.address);
    const adminBal = await wallyToken.balanceOf(admin.address);

    // The contractBal should be around half
    expect(contractBal).to.be.closeTo(vestedBeforeRevoke, 5);

    // beneficiary can still release the vested portion
    await vesting.connect(beneficiary).release();
    const finalBeneficiaryBal = await wallyToken.balanceOf(beneficiary.address);
    expect(finalBeneficiaryBal).to.be.gt(0).and.lte(contractBal);
  });
});