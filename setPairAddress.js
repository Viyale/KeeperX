const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();

  // Replace the following with your actual deployed contract address
  const contractAddress = "0x14423Dc81D57ae8a5ca654b86DDFd450226c9a76";

  // Replace the following with your actual PancakeSwap KPX/USDT pair address
  const newPairAddress = "0x3a22Ab0a0eBB11BE6865A414506efD03Dee3baD0"; 

  console.log("Setting new pair address to:", newPairAddress);

  // Attach to the deployed contract
  const KeeperCoinRebase = await ethers.getContractFactory("KeeperCoinRebase");
  const contract = KeeperCoinRebase.attach(contractAddress);

  // Update the pair address using the setPairAddress function
  const tx = await contract.connect(deployer).setPairAddress(newPairAddress);
  await tx.wait();
  
  console.log("New pair address set successfully:", newPairAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
