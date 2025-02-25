const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("WallyToken", function () {
  let Token, token;
  let owner, dao, alice, bob;
  let routerMock; // If needed as a placeholder for _uniswapV2Router

  before(async () => {
    [owner, dao, alice, bob, ...addrs] = await ethers.getSigners();

    // Deploy a mock router (if needed for constructor argument)
    // For a real test, you'd deploy or reference an actual Uniswap router on a testnet
    const RouterMock = await ethers.getContractFactory("MockUniswapRouter"); 
    routerMock = await RouterMock.deploy();
    await routerMock.deployed();
  });

  beforeEach(async () => {
    // Deploy WallyToken
    const TokenFactory = await ethers.getContractFactory("WallyToken");
    token = await TokenFactory.deploy(routerMock.address); 
    await token.deployed();
  });

  it("Should have correct name and symbol", async function () {
    expect(await token.name()).to.equal("Wally Token");
    expect(await token.symbol()).to.equal("TWG");
  });

  it("Should mint initial supply to deployer (owner)", async function () {
    const deployerBalance = await token.balanceOf(owner.address);
    const totalSupply = await token.totalSupply();
    expect(deployerBalance).to.equal(totalSupply);
  });

  it("DAO should have ADMIN_ROLE, but deployer does not", async function () {
    // ADMIN_ROLE is keccak256("ADMIN_ROLE")
    const ADMIN_ROLE = await token.ADMIN_ROLE();
    // Check that DAO is admin
    expect(await token.hasRole(ADMIN_ROLE, dao.address)).to.be.true;
    // The deployer (owner) should NOT have admin
    expect(await token.hasRole(ADMIN_ROLE, owner.address)).to.be.false;
  });

  it("Admin can set tradingEnabled", async function () {
    // Initially false
    expect(await token.tradingEnabled()).to.be.false;

    // Attempt from deployer => revert
    await expect(token.setTradingEnabled(true)).to.be.revertedWith(
      "AccessControl: account " + owner.address.toLowerCase() + " is missing role"
    );

    // Call from DAO => success
    await token.connect(dao).setTradingEnabled(true);
    expect(await token.tradingEnabled()).to.be.true;
  });

  it("Should block transfers if trading is disabled (unless admin)", async function () {
    // tradingEnabled is false by default
    await expect(token.connect(alice).transfer(bob.address, 100)).to.be.revertedWith(
      "WallyToken: Trading is disabled"
    );

    // Admin can still transfer
    const ADMIN_ROLE = await token.ADMIN_ROLE();
    // Let dao transfer some tokens from the deployer (owner) supply to itself
    // Actually, dao has no tokens yet. We can do from owner => dao
    await token.connect(owner).transfer(dao.address, 1000);
    await token.connect(dao).transfer(bob.address, 500); // works because dao is admin
    expect(await token.balanceOf(bob.address)).to.equal(500);
  });

  it("Should blacklist addresses", async function () {
    // Enable trading to test blacklisting effect
    await token.connect(dao).setTradingEnabled(true);

    // Blacklist bob
    await token.connect(dao).setBlacklist(bob.address, true);
    expect(await token.blacklist(bob.address)).to.be.true;

    // Bob can no longer transfer or receive tokens
    // Transfer some tokens to bob (from owner)
    await expect(token.connect(owner).transfer(bob.address, 100)).to.be.revertedWith(
      "WallyToken: Recipient blacklisted"
    );
  });

  it("Should enforce maxTxAmount if set", async function () {
    // enable trading
    await token.connect(dao).setTradingEnabled(true);

    // Set max tx to 500
    await token.connect(dao).setMaxTxAmount(500);

    // Transfer 1000 from owner to alice => revert
    await expect(token.connect(owner).transfer(alice.address, 1000)).to.be.revertedWith(
      "WallyToken: Exceeds maxTxAmount"
    );

    // Transfer 500 => success
    await token.connect(owner).transfer(alice.address, 500);
    expect(await token.balanceOf(alice.address)).to.equal(500);
  });

  it("Should allow admin to mint tokens", async function () {
    // By default, MINTER_ROLE is subordinate to ADMIN_ROLE, but nobody has MINTER_ROLE yet.
    // The DAO can grant itself the MINTER_ROLE
    const MINTER_ROLE = await token.MINTER_ROLE();
    const ADMIN_ROLE = await token.ADMIN_ROLE();

    // dao grants itself MINTER_ROLE
    await token.connect(dao).grantRole(MINTER_ROLE, dao.address);

    // Check that dao can now mint
    const oldSupply = await token.totalSupply();
    await token.connect(dao).mint(dao.address, 10000);
    const newSupply = await token.totalSupply();
    expect(newSupply).to.equal(oldSupply.add(10000));
  });

  it("Should allow admin to burn tokens", async function () {
    // Similar to minting
    const BURNER_ROLE = await token.BURNER_ROLE();
    await token.connect(dao).grantRole(BURNER_ROLE, dao.address);

    // dao transfers some tokens to itself
    await token.connect(owner).transfer(dao.address, 1000);

    // dao burns
    const oldSupply = await token.totalSupply();
    await token.connect(dao).burn(500);
    const newSupply = await token.totalSupply();
    expect(newSupply).to.equal(oldSupply.sub(500));
  });

  // For advanced anti-sniping & cooldown, you'd need to manipulate blocks/time, which can be tested
  // using hardhat evm_increaseTime, evm_mine, or ethers.provider.send(...) calls.

  it("Should rescue tokens (Admin only)", async function () {
    const ADMIN_ROLE = await token.ADMIN_ROLE();
    // Transfer some TWG to the token contract
    await token.connect(owner).transfer(token.address, 1000);

    // Attempt from non-admin => revert
    await expect(token.rescueTokens(token.address, 500, alice.address)).to.be.reverted;

    // Admin call => success
    await token.connect(dao).rescueTokens(token.address, 500, alice.address);
    expect(await token.balanceOf(alice.address)).to.equal(500);
  });
});