import { expect } from "chai";
import { network } from "hardhat";

let ethers: any;
before(async () => { ethers = (await network.getOrCreate()).ethers; });

async function expectRevert(
  promise: Promise<unknown>,
  msg?: string
): Promise<void> {
  try {
    await promise;
    throw new Error("Expected transaction to revert");
  } catch (e: any) {
    if (e.message === "Expected transaction to revert") throw e;
    if (msg) expect(e.message).to.include(msg);
  }
}

describe("VaultOFT", () => {
  let vaultOFT: any;
  let executor: any;
  let owner: any;
  let user: any;

  beforeEach(async () => {
    [owner, user] = await ethers.getSigners();

    const VaultOFTFactory = await ethers.getContractFactory("VaultOFT");
    vaultOFT = await VaultOFTFactory.deploy(owner.address, owner.address);

    const ExecutorFactory = await ethers.getContractFactory(
      "EthStrategyExecutor"
    );
    executor = await ExecutorFactory.deploy(
      await vaultOFT.getAddress(),
      owner.address
    );

    await vaultOFT.setStrategyExecutor(await executor.getAddress());
  });

  it("deploys with correct name and symbol", async () => {
    expect(await vaultOFT.name()).to.equal("Wrapped APT");
    expect(await vaultOFT.symbol()).to.equal("wAPT");
  });

  it("sets strategy executor", async () => {
    expect(await vaultOFT.strategyExecutor()).to.equal(
      await executor.getAddress()
    );
  });

  it("encodes and decodes payload correctly", async () => {
    const action = 1;
    const strategyId = 42;
    const vaultAddr = ethers.zeroPadValue("0x1234", 32);
    const nonce = 7n;

    const encoded = await vaultOFT.encodePayload(
      action,
      strategyId,
      vaultAddr,
      nonce
    );
    const decoded = await vaultOFT.decodePayload(encoded);

    expect(decoded.action).to.equal(action);
    expect(decoded.strategyId).to.equal(strategyId);
    expect(decoded.vaultAddr).to.equal(vaultAddr);
    expect(decoded.nonce).to.equal(nonce);
  });

  it("rejects non-executor mint", async () => {
    await expectRevert(
      vaultOFT.connect(user).mintBridge(user.address, 100n),
      "VaultOFT: not executor"
    );
  });
});

describe("EthStrategyExecutor", () => {
  let vaultOFT: any;
  let executor: any;
  let owner: any;

  beforeEach(async () => {
    [owner] = await ethers.getSigners();

    const VaultOFTFactory = await ethers.getContractFactory("VaultOFT");
    vaultOFT = await VaultOFTFactory.deploy(owner.address, owner.address);

    const ExecutorFactory = await ethers.getContractFactory(
      "EthStrategyExecutor"
    );
    executor = await ExecutorFactory.deploy(
      await vaultOFT.getAddress(),
      owner.address
    );

    await vaultOFT.setStrategyExecutor(await executor.getAddress());
  });

  it("deploys with correct oft address", async () => {
    expect(await executor.oft()).to.equal(await vaultOFT.getAddress());
  });

  it("rejects executeIncoming from non-OFT caller", async () => {
    const payload = await vaultOFT.encodePayload(
      1,
      0,
      ethers.zeroPadValue("0x01", 32),
      1n
    );
    await expectRevert(
      executor.connect(owner).executeIncoming(100n, payload),
      "Executor: only OFT"
    );
  });

  it("rejects unknown action via impersonation", async () => {
    await ethers.provider.send("hardhat_impersonateAccount", [
      await vaultOFT.getAddress(),
    ]);
    await ethers.provider.send("hardhat_setBalance", [
      await vaultOFT.getAddress(),
      "0x1000000000000000000",
    ]);
    const oftSigner = await ethers.getSigner(await vaultOFT.getAddress());

    const payload = await vaultOFT.encodePayload(
      0xff,
      0,
      ethers.zeroPadValue("0x01", 32),
      1n
    );
    await expectRevert(
      executor.connect(oftSigner).executeIncoming(100n, payload),
      "Executor: unknown action"
    );

    await ethers.provider.send("hardhat_stopImpersonatingAccount", [
      await vaultOFT.getAddress(),
    ]);
  });
});
