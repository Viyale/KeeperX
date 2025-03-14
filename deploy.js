const { ethers } = require("hardhat");

async function main() {
  console.log("Deploying KeeperX (KPX) Token...");

  // Get the deployer's (owner's) address
  const [deployer] = await ethers.getSigners();
  // Use the deployer's address as a temporary pair address during deployment
  const temporaryPairAddress = deployer.address;

  // Get the contract factory for KeeperCoinRebase
  const KeeperCoinRebase = await ethers.getContractFactory("KeeperCoinRebase");
  
  // Deploy the contract with the temporary pair address and a gasPrice of 5 gwei
  const keeperCoin = await KeeperCoinRebase.deploy(temporaryPairAddress, {
    gasPrice: ethers.utils.parseUnits("5", "gwei")
  });
  await keeperCoin.deployed();

  // Save and print the deployed contract address for later use
  const deployedContractAddress = keeperCoin.address;
  console.log("KeeperX Token deployed to:", deployedContractAddress);
  console.log("Temporary Pair Address (used in constructor):", temporaryPairAddress);

  // After deployment, create the KPX/USDT pair on PancakeSwap,
  // then update the pair address using the setPairAddress script.
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
