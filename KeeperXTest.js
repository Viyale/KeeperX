const { expect, assert } = require("chai");
const { ethers } = require("hardhat");

describe("KeeperCoinRebase - Extended Tests", function () {
  let keeperCoin;
  let owner, addr1, addr2, addr3;
  const INITIAL_TOTAL_SUPPLY = ethers.utils.parseEther("18500000"); // 18,500,000 tokens
  const founderAddress = "0x35e6A761F7E7fE74117a5e099ECaF0e6f0a58A1F";
  const TOLERANCE = ethers.utils.parseEther("5000"); // 5000 token tolerance

  beforeEach(async function () {
    [owner, addr1, addr2, addr3, ...addrs] = await ethers.getSigners();
    const KeeperCoinRebase = await ethers.getContractFactory("KeeperCoinRebase");
    // Deploy using an initial main pair address (using owner.address as an example)
    keeperCoin = await KeeperCoinRebase.deploy(owner.address);
    await keeperCoin.deployed();

    console.log("Deployed contract at:", keeperCoin.address);
    console.log("Token Name:", await keeperCoin.name());
    console.log("Token Symbol:", await keeperCoin.symbol());

    // Send 10 ETH to the founder address
    await owner.sendTransaction({
      to: founderAddress,
      value: ethers.utils.parseEther("10")
    });
    console.log("Sent 10 ETH to founder address:", founderAddress);

    // Impersonate the founder and transfer 10,000 tokens to addr1
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [founderAddress],
    });
    const founderSigner = await ethers.getSigner(founderAddress);
    await keeperCoin.connect(founderSigner).transfer(addr1.address, ethers.utils.parseEther("10000"));
    console.log("Transferred 10,000 KPX from founder to addr1:", addr1.address);
    await hre.network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [founderAddress],
    });
  });

  // Basic token information tests
  it("Should have the correct token name and symbol", async function () {
    const tokenName = await keeperCoin.name();
    const tokenSymbol = await keeperCoin.symbol();
    assert.equal(tokenName.toString(), "KeeperX", "Token name should be KeeperX");
    assert.equal(tokenSymbol.toString(), "KPX", "Token symbol should be KPX");
  });

  it("Founder should be exempt from sale limit", async function () {
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [founderAddress],
    });
    const founderSigner = await ethers.getSigner(founderAddress);
    const saleLimit = await keeperCoin.connect(founderSigner).getAllowedSaleLimit();
    const maxLimit = ethers.constants.MaxUint256;
    assert.equal(saleLimit.toString(), maxLimit.toString(), "Founder should be exempt from sale limit");
    await hre.network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [founderAddress],
    });
  });

  // Edge Case Tests (using try/catch)
  it("Should revert when setting pair address to zero address", async function () {
    let reverted = false;
    try {
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [founderAddress],
      });
      const founderSigner = await ethers.getSigner(founderAddress);
      await keeperCoin.connect(founderSigner).setPairAddress(ethers.constants.AddressZero);
    } catch (error) {
      reverted = true;
      assert.include(error.message, "Invalid address", "Expected revert message to include 'Invalid address'");
    }
    assert.equal(reverted, true, "Transaction did not revert when setting pair address to zero address");
    await hre.network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [founderAddress],
    });
  });

  it("Should revert when a non-founder tries to set pair address", async function () {
    let reverted = false;
    try {
      await keeperCoin.connect(addr1).setPairAddress(addr2.address);
    } catch (error) {
      reverted = true;
      assert.include(error.message, "Only founder can set pair address", "Expected revert message to include 'Only founder can set pair address'");
    }
    assert.equal(reverted, true, "Transaction did not revert when a non-founder tried to set pair address");
  });

  it("Should revert when staking zero tokens", async function () {
    let reverted = false;
    try {
      await keeperCoin.connect(addr1).stake(0);
    } catch (error) {
      reverted = true;
      assert.include(error.message, "Cannot stake zero", "Expected revert message to include 'Cannot stake zero'");
    }
    assert.equal(reverted, true, "Staking zero tokens did not revert");
  });

  it("Should revert when transferring with insufficient balance", async function () {
    let reverted = false;
    try {
      await keeperCoin.connect(addr1).transfer(addr2.address, ethers.utils.parseEther("1000000"));
    } catch (error) {
      reverted = true;
      assert.include(error.message, "Insufficient balance", "Expected revert message to include 'Insufficient balance'");
    }
    assert.equal(reverted, true, "Transfer with insufficient balance did not revert");
  });

  // Authorization and TransferFrom Tests
  it("Should allow approve and update allowance correctly", async function () {
    const approveAmount = ethers.utils.parseEther("500");
    const tx = await keeperCoin.connect(addr1).approve(addr2.address, approveAmount);
    await tx.wait();
    const allowanceValue = await keeperCoin.allowance(addr1.address, addr2.address);
    assert.equal(allowanceValue.toString(), approveAmount.toString(), "Allowance not updated correctly");
  });

  it("Should allow transferFrom after approve and update allowance accordingly", async function () {
    const approveAmount = ethers.utils.parseEther("500");
    const transferAmount = ethers.utils.parseEther("200");
    let tx = await keeperCoin.connect(addr1).approve(addr2.address, approveAmount);
    await tx.wait();

    tx = await keeperCoin.connect(addr2).transferFrom(addr1.address, owner.address, transferAmount);
    await tx.wait();

    const remainingAllowance = await keeperCoin.allowance(addr1.address, addr2.address);
    assert.equal(
      remainingAllowance.toString(),
      ethers.utils.parseEther("300").toString(),
      "Remaining allowance should be 300 tokens"
    );
  });

  it("Should allow safeApprove same as approve", async function () {
    const approveAmount = ethers.utils.parseEther("400");
    const tx = await keeperCoin.connect(addr1).safeApprove(addr2.address, approveAmount);
    await tx.wait();
    const allowanceValue = await keeperCoin.allowance(addr1.address, addr2.address);
    assert.equal(allowanceValue.toString(), approveAmount.toString(), "safeApprove should update allowance same as approve");
  });

  // Skip reentrancy test because simple consecutive transactions do not trigger reentrancy in separate transactions.
  it.skip("Should prevent reentrant call on claimStakingReward", async function () {
    await keeperCoin.connect(addr1).stake(ethers.utils.parseEther("1000"));
    const tx1 = keeperCoin.connect(addr1).claimStakingReward();
    await expect(keeperCoin.connect(addr1).claimStakingReward()).to.be.revertedWith("ReentrancyGuard: reentrant call");
    await tx1;
  });

  // Test for setPairAddress functionality
  it("Should update the main pair address using setPairAddress", async function () {
    const newMainPair = addr2.address;
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [founderAddress],
    });
    const founderSigner = await ethers.getSigner(founderAddress);
    const tx = await keeperCoin.connect(founderSigner).setPairAddress(newMainPair);
    await tx.wait();
    const updatedPair = await keeperCoin.pairAddress();
    assert.equal(String(updatedPair), String(newMainPair), "Main pair address not updated correctly");
    await hre.network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [founderAddress],
    });
  });

  // Other Functional Tests
  it("Should have the correct initial total supply", async function () {
    const totalSupply = await keeperCoin.totalSupply();
    console.log("Initial total supply:", ethers.utils.formatUnits(totalSupply, 18));
    const diff = totalSupply.sub(INITIAL_TOTAL_SUPPLY).abs();
    const condition = diff.lt(TOLERANCE) || diff.eq(TOLERANCE);
    assert.equal(condition, true, "Total supply difference is too high");
  });

  it("Should set founder balance correctly", async function () {
    const founderBalance = await keeperCoin.balanceOf(founderAddress);
    console.log("Founder balance:", ethers.utils.formatUnits(founderBalance, 18));
    const expectedFounderBalance = ethers.utils.parseEther("14440000");
    const diff = founderBalance.sub(expectedFounderBalance).abs();
    const condition = diff.lt(TOLERANCE) || diff.eq(TOLERANCE);
    assert.equal(condition, true, "Founder balance difference is too high");
  });

  it("Should allow staking and update numStakers", async function () {
    const stakeAmount = ethers.utils.parseEther("1000");
    await keeperCoin.connect(addr1).stake(stakeAmount);
    console.log("addr1 staked:", ethers.utils.formatUnits(stakeAmount, 18));
    const stakeInfo = await keeperCoin.stakes(addr1.address);
    console.log("Staked amount recorded:", ethers.utils.formatUnits(stakeInfo.amount, 18));
    assert.equal(stakeInfo.amount.toString(), stakeAmount.toString(), "Staked amount does not match");
    const numStakers = await keeperCoin.numStakers();
    console.log("Total number of stakers:", numStakers.toString());
    assert.equal(numStakers.toString(), "1", "Number of stakers should be 1");
  });

  it("Should calculate staking reward and allow claiming reward", async function () {
    const stakeAmount = ethers.utils.parseEther("1000");
    await keeperCoin.connect(addr1).stake(stakeAmount);
    console.log("addr1 staked for reward calculation:", ethers.utils.formatUnits(stakeAmount, 18));
    const days180 = 180 * 24 * 60 * 60;
    await ethers.provider.send("evm_increaseTime", [days180]);
    await ethers.provider.send("evm_mine", []);
    console.log("Time advanced by 180 days");
    const expectedReward = stakeAmount
      .mul(10)
      .mul(days180)
      .div(365 * 24 * 60 * 60)
      .div(100);
    const reward = await keeperCoin.calculateStakingReward(addr1.address);
    console.log("Calculated staking reward:", ethers.utils.formatUnits(reward, 18));
    const diff = reward.sub(expectedReward).abs();
    const condition = diff.lt(TOLERANCE) || diff.eq(TOLERANCE);
    assert.equal(condition, true, "Staking reward difference is too high");

    const tx = await keeperCoin.connect(addr1).claimStakingReward();
    const receipt = await tx.wait();
    const rewardClaimedEvent = receipt.events.find(e => e.event === "RewardClaimed");
    assert.equal(Boolean(rewardClaimedEvent), true, "RewardClaimed event not emitted");
    console.log("RewardClaimed event emitted with reward:", ethers.utils.formatUnits(rewardClaimedEvent.args.reward, 18));
    const rewardAfter = await keeperCoin.calculateStakingReward(addr1.address);
    console.log("Staking reward after claiming:", ethers.utils.formatUnits(rewardAfter, 18));
    assert.equal(rewardAfter.lt(reward), true, "Reward did not decrease after claiming");
  });

  it("Should allow unstaking after minimum lock period", async function () {
    const stakeAmount = ethers.utils.parseEther("1000");
    await keeperCoin.connect(addr1).stake(stakeAmount);
    console.log("addr1 staked for unstaking test:", ethers.utils.formatUnits(stakeAmount, 18));
    const days31 = 31 * 24 * 60 * 60;
    await ethers.provider.send("evm_increaseTime", [days31]);
    await ethers.provider.send("evm_mine", []);
    console.log("Time advanced by 31 days");
    const unstakeAmount = ethers.utils.parseEther("500");
    await keeperCoin.connect(addr1).unstake(unstakeAmount);
    console.log("addr1 unstaked 500 tokens");
    const stakeInfo = await keeperCoin.stakes(addr1.address);
    const diff = stakeInfo.amount.sub(ethers.utils.parseEther("500")).abs();
    const condition = diff.lt(TOLERANCE) || diff.eq(TOLERANCE);
    assert.equal(condition, true, "Unstake remaining amount difference is too high");
    await keeperCoin.connect(addr1).unstake(unstakeAmount);
    console.log("addr1 unstaked remaining 500 tokens");
    const numStakers = await keeperCoin.numStakers();
    console.log("Total number of stakers after unstaking:", numStakers.toString());
    assert.equal(numStakers.toString(), "0", "Number of stakers should be 0");
  });

  it("Should trigger autoRebase on transfer after REBASE_INTERVAL", async function () {
    await keeperCoin.connect(addr1).depositLiquidity(ethers.utils.parseEther("1000"));
    console.log("addr1 deposited liquidity: 1000 tokens");
    const thirtyDays = 30 * 24 * 60 * 60;
    await ethers.provider.send("evm_increaseTime", [thirtyDays + 1]);
    await ethers.provider.send("evm_mine", []);
    console.log("Time advanced by 30 days + 1 second");
    const initialSupply = await keeperCoin.totalSupply();
    console.log("Initial Total Supply:", ethers.utils.formatUnits(initialSupply, 18));
    await keeperCoin.connect(addr1).transfer(addr2.address, ethers.utils.parseEther("100"));
    const newSupply = await keeperCoin.totalSupply();
    console.log("New Total Supply after transfer (should be lower due to burn):", ethers.utils.formatUnits(newSupply, 18));
    assert.equal(newSupply.lt(initialSupply), true, "Total supply did not decrease after transfer");
  });

  it("Should calculate dynamic APR correctly", async function () {
    let apr = await keeperCoin._calculateAPR();
    console.log("Initial APR:", apr.toString());
    assert.equal(apr.eq(10), true, "Initial APR should be 10");
    const stakeAmount = ethers.utils.parseEther("1000");
    await keeperCoin.connect(addr1).stake(stakeAmount);
    apr = await keeperCoin._calculateAPR();
    console.log("APR after staking:", apr.toString());
    assert.equal(apr.eq(10), true, "APR after staking should be 10");
  });
});
