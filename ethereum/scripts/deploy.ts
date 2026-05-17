import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with:", deployer.address);

  const VaultOFT = await ethers.getContractFactory("VaultOFT");
  const vaultOFT = await VaultOFT.deploy(deployer.address);
  await vaultOFT.waitForDeployment();
  console.log("VaultOFT deployed to:", await vaultOFT.getAddress());

  const EthStrategyExecutor = await ethers.getContractFactory("EthStrategyExecutor");
  const executor = await EthStrategyExecutor.deploy(
    await vaultOFT.getAddress(),
    deployer.address
  );
  await executor.waitForDeployment();
  console.log("EthStrategyExecutor deployed to:", await executor.getAddress());

  await vaultOFT.setStrategyExecutor(await executor.getAddress());
  console.log("VaultOFT executor set");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
