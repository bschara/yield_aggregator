import { expect } from "chai";
import { network } from "hardhat";

let ethers: any;

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

// ── Constants ────────────────────────────────────────────────────────────────

const ETH_CHAIN_ID = 101;
const APTOS_CHAIN_ID = 108;

const ACTION_DEPLOY = 0x01;
const ACTION_RECALL = 0x02;
const ACTION_COMPLETE = 0x04;

// Fake 32-byte Aptos vault address used in payloads
const MOCK_VAULT_ADDR = ethers.zeroPadValue("0xABCD", 32);

// ── Payload helpers (must match VaultOFT.encodePayload / oft_bridge.move) ──

function encodePayload(
  action: number,
  amount: bigint,
  strategyId: bigint,
  nonce: bigint,
  vaultAddr: string
): string {
  return ethers.solidityPacked(
    ["uint8", "uint64", "uint64", "uint64", "bytes32"],
    [action, amount, strategyId, nonce, vaultAddr]
  );
}

function decodeAction(payload: string): number {
  return parseInt(payload.slice(2, 4), 16);
}

// ── Fixture (deploy once, snapshot, restore per test) ────────────────────────

let snap: string;
let ethEndpoint: any,
  aptosEndpoint: any,
  vaultOFT: any,
  executor: any,
  fakeAptos: any;
let deployer: any, user: any;

// Trusted remote path that VaultOFT accepts for messages from "Aptos chain 108"
let trustedRemotePath: string;
// Source address used when test delivers a message into ethEndpoint
let aptosSrcPath: string;

async function deploy() {
  [deployer, user] = await ethers.getSigners();

  // Two LZEndpointMock instances — one per "chain"
  ethEndpoint = await ethers.deployContract("LZEndpointMock", [ETH_CHAIN_ID]);
  aptosEndpoint = await ethers.deployContract("LZEndpointMock", [
    APTOS_CHAIN_ID,
  ]);

  // VaultOFT on the ETH endpoint
  vaultOFT = await ethers.deployContract("VaultOFT", [
    await ethEndpoint.getAddress(),
    deployer.address,
  ]);

  // FakeAptosReceiver behind the Aptos endpoint (stand-in for oft_bridge.move)
  fakeAptos = await ethers.deployContract("FakeAptosReceiver", [
    await aptosEndpoint.getAddress(),
  ]);

  // Executor
  executor = await ethers.deployContract("EthStrategyExecutor", [
    await vaultOFT.getAddress(),
    deployer.address,
  ]);
  await vaultOFT.setStrategyExecutor(await executor.getAddress());

  // Wire ETH endpoint: vaultOFT sends → route through aptosEndpoint → fakeAptos
  await ethEndpoint.setRoute(
    await vaultOFT.getAddress(),
    await aptosEndpoint.getAddress(),
    await fakeAptos.getAddress()
  );
  await ethEndpoint.setCallReceive(true);

  // Trusted remote: VaultOFT accepts messages where srcAddress == this path
  // Format: abi.encodePacked(remoteSender, localReceiver)
  // We use fakeAptos as the stand-in remote sender (its address as 20 bytes)
  const fakeAptosAddr = await fakeAptos.getAddress();
  const vaultOFTAddr = await vaultOFT.getAddress();
  trustedRemotePath = ethers.concat([fakeAptosAddr, vaultOFTAddr]);
  await vaultOFT.setTrustedRemote(APTOS_CHAIN_ID, trustedRemotePath);

  // aptosSrcPath used when calling ethEndpoint.receivePayload — must equal trustedRemotePath
  aptosSrcPath = trustedRemotePath;

  // Set Aptos bridge address on executor (used to build the LZ destination for send-back)
  // Encode fakeAptos address as 32 bytes so the executor packs it correctly
  const fakeAptosBytes32 = ethers.zeroPadValue(fakeAptosAddr, 32);
  await executor.setAptosBridgeAddress(fakeAptosBytes32 as any);

  // Fund executor with ETH to pay LZ fees when sending back to Aptos
  await deployer.sendTransaction({
    to: await executor.getAddress(),
    value: ethers.parseEther("1"),
  });
}

before(async () => {
  ethers = (await network.getOrCreate()).ethers;
  await deploy();
  snap = await ethers.provider.send("evm_snapshot", []);
});

afterEach(async () => {
  await ethers.provider.send("evm_revert", [snap]);
  snap = await ethers.provider.send("evm_snapshot", []);
});

// ── Tests ────────────────────────────────────────────────────────────────────

describe("Bridge E2E — Ethereum side (no testnet)", () => {
  it("inbound nonce advances when ethEndpoint delivers to VaultOFT", async () => {
    const nonceBefore = await ethEndpoint.getInboundNonce(
      APTOS_CHAIN_ID,
      aptosSrcPath
    );
    const payload = encodePayload(
      ACTION_DEPLOY,
      100_000_000n,
      0n,
      1n,
      MOCK_VAULT_ADDR
    );

    await ethEndpoint.receivePayload(
      APTOS_CHAIN_ID,
      aptosSrcPath,
      await vaultOFT.getAddress(),
      1,
      payload
    );

    expect(
      await ethEndpoint.getInboundNonce(APTOS_CHAIN_ID, aptosSrcPath)
    ).to.equal(nonceBefore + 1n);
  });

  it("trusted remote validated: wrong src address reverts", async () => {
    const wrongPath = ethers.concat([
      ethers.zeroPadValue("0xDEAD", 20),
      await vaultOFT.getAddress(),
    ]);
    const payload = encodePayload(
      ACTION_DEPLOY,
      100_000_000n,
      0n,
      1n,
      MOCK_VAULT_ADDR
    );

    await expectRevert(
      ethEndpoint.receivePayload(
        APTOS_CHAIN_ID,
        wrongPath,
        await vaultOFT.getAddress(),
        1,
        payload
      ),
      "VaultOFT: untrusted remote"
    );
  });

  it("DEPLOY: wAPT minted to executor, deployedAmounts updated", async () => {
    const amount = 200_000_000n;
    const payload = encodePayload(
      ACTION_DEPLOY,
      amount,
      0n,
      1n,
      MOCK_VAULT_ADDR
    );

    await ethEndpoint.receivePayload(
      APTOS_CHAIN_ID,
      aptosSrcPath,
      await vaultOFT.getAddress(),
      1,
      payload
    );

    expect(await vaultOFT.balanceOf(await executor.getAddress())).to.equal(
      amount
    );
    expect(await executor.deployedAmounts(0)).to.equal(amount);
  });

  it("RECALL: executor burns wAPT and auto-delivers COMPLETE to FakeAptosReceiver", async () => {
    const amount = 100_000_000n;

    // First deploy so the executor has deployed capital to recall from
    const deployPayload = encodePayload(
      ACTION_DEPLOY,
      amount,
      0n,
      1n,
      MOCK_VAULT_ADDR
    );
    await ethEndpoint.receivePayload(
      APTOS_CHAIN_ID,
      aptosSrcPath,
      await vaultOFT.getAddress(),
      1,
      deployPayload
    );

    const recallPayload = encodePayload(
      ACTION_RECALL,
      amount,
      0n,
      2n,
      MOCK_VAULT_ADDR
    );
    await ethEndpoint.receivePayload(
      APTOS_CHAIN_ID,
      aptosSrcPath,
      await vaultOFT.getAddress(),
      2,
      recallPayload
    );

    // Executor burned wAPT
    expect(await vaultOFT.balanceOf(await executor.getAddress())).to.equal(0n);
    expect(await executor.deployedAmounts(0)).to.equal(0n);

    // COMPLETE message auto-delivered to FakeAptosReceiver via endpoint routing
    expect(await fakeAptos.receivedCount()).to.equal(1);
    const msg = await fakeAptos.lastMessage();
    expect(msg.srcChainId).to.equal(ETH_CHAIN_ID);
    expect(decodeAction(msg.payload)).to.equal(ACTION_COMPLETE);
  });

  it("outbound nonce increments when executor sends back to Aptos", async () => {
    const amount = 100_000_000n;
    const deployPayload = encodePayload(
      ACTION_DEPLOY,
      amount,
      0n,
      1n,
      MOCK_VAULT_ADDR
    );
    await ethEndpoint.receivePayload(
      APTOS_CHAIN_ID,
      aptosSrcPath,
      await vaultOFT.getAddress(),
      1,
      deployPayload
    );

    const nonceBefore = await ethEndpoint.getOutboundNonce(
      APTOS_CHAIN_ID,
      await vaultOFT.getAddress()
    );

    const recallPayload = encodePayload(
      ACTION_RECALL,
      amount,
      0n,
      2n,
      MOCK_VAULT_ADDR
    );
    await ethEndpoint.receivePayload(
      APTOS_CHAIN_ID,
      aptosSrcPath,
      await vaultOFT.getAddress(),
      2,
      recallPayload
    );

    expect(
      await ethEndpoint.getOutboundNonce(
        APTOS_CHAIN_ID,
        await vaultOFT.getAddress()
      )
    ).to.equal(nonceBefore + 1n);
  });

  it("fee too low: send() reverts with insufficient fee error", async () => {
    const amount = 100_000_000n;
    const deployPayload = encodePayload(
      ACTION_DEPLOY,
      amount,
      0n,
      1n,
      MOCK_VAULT_ADDR
    );
    await ethEndpoint.receivePayload(
      APTOS_CHAIN_ID,
      aptosSrcPath,
      await vaultOFT.getAddress(),
      1,
      deployPayload
    );

    // Drain executor ETH so it has 0 balance
    await ethers.provider.send("hardhat_setBalance", [
      await executor.getAddress(),
      "0x0",
    ]);

    const recallPayload = encodePayload(
      ACTION_RECALL,
      amount,
      0n,
      2n,
      MOCK_VAULT_ADDR
    );
    // The recall triggers _sendBackToAptos which calls lzSend with 0 ETH — should revert
    await expectRevert(
      ethEndpoint.receivePayload(
        APTOS_CHAIN_ID,
        aptosSrcPath,
        await vaultOFT.getAddress(),
        2,
        recallPayload
      )
    );
  });

  it("blocking: blockNextMsg stores message, forceResumeReceive delivers it", async () => {
    const amount = 100_000_000n;
    const deployPayload = encodePayload(
      ACTION_DEPLOY,
      amount,
      0n,
      1n,
      MOCK_VAULT_ADDR
    );
    await ethEndpoint.receivePayload(
      APTOS_CHAIN_ID,
      aptosSrcPath,
      await vaultOFT.getAddress(),
      1,
      deployPayload
    );

    // Block the next outbound message
    await ethEndpoint.blockNextMsg();

    const recallPayload = encodePayload(
      ACTION_RECALL,
      amount,
      0n,
      2n,
      MOCK_VAULT_ADDR
    );
    await ethEndpoint.receivePayload(
      APTOS_CHAIN_ID,
      aptosSrcPath,
      await vaultOFT.getAddress(),
      2,
      recallPayload
    );

    // Executor ran, wAPT burned — but COMPLETE message is blocked
    expect(await fakeAptos.receivedCount()).to.equal(0);
    expect(await ethEndpoint.hasBlocked()).to.equal(true);

    // Resume delivery
    await ethEndpoint.forceResumeReceive(ETH_CHAIN_ID, ethers.toUtf8Bytes(""));

    expect(await fakeAptos.receivedCount()).to.equal(1);
    expect(decodeAction((await fakeAptos.lastMessage()).payload)).to.equal(
      ACTION_COMPLETE
    );
  });
});
