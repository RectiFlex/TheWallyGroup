const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("WallyAirdrop", function () {
  let WallyToken, wallyToken;
  let WallyAirdrop, airdrop;
  let admin, user1, user2, user3;

  before(async () => {
    [admin, user1, user2, user3] = await ethers.getSigners();

    // Deploy WallyToken
    const TokenFactory = await ethers.getContractFactory("WallyToken");
    wallyToken = await TokenFactory.deploy(admin.address); 
    await wallyToken.deployed();
  });

  beforeEach(async () => {
    // Deploy WallyAirdrop
    const AirdropFactory = await ethers.getContractFactory("WallyAirdrop");
    airdrop = await AirdropFactory.deploy(wallyToken.address, admin.address);
    await airdrop.deployed();

    // Admin -> Transfer some tokens to airdrop for distribution
    await wallyToken.connect(admin).transfer(airdrop.address, 5000);
  });

  it("Should only let ADMIN_ROLE do airdrops", async () => {
    // user1 tries to airdrop => revert
    await expect(
      airdrop.connect(user1).airdrop([user2.address], [100])
    ).to.be.revertedWith("AccessControl");

    // Admin call => success
    await airdrop.connect(admin).airdrop([user2.address, user3.address], [100, 200]);
    expect(await wallyToken.balanceOf(user2.address)).to.equal(100);
    expect(await wallyToken.balanceOf(user3.address)).to.equal(200);
  });

  it("Should revert if arrays mismatch in length", async () => {
    await expect(
      airdrop.connect(admin).airdrop([user2.address, user3.address], [100])
    ).to.be.revertedWith("Length mismatch");
  });

  it("Should revert if insufficient contract balance", async () => {
    // We only transferred 5000 to the contract
    await expect(
      airdrop.connect(admin).airdrop([user1.address], [6000])
    ).to.be.revertedWith("Insufficient balance");
  });

  it("Should rescue tokens (ADMIN only)", async () => {
    // user tries => fail
    await expect(
      airdrop.connect(user1).rescueTokens(wallyToken.address, 1000, user1.address)
    ).to.be.revertedWith("AccessControl");

    // Admin => success
    await airdrop.connect(admin).rescueTokens(wallyToken.address, 1000, user1.address);
    expect(await wallyToken.balanceOf(user1.address)).to.equal(1000);
  });
});