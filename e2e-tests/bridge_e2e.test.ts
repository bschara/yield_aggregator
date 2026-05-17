/**
 * Cross-VM E2E test: Aptos ↔ Ethereum bridge round-trip.
 *
 * Prerequisites:
 *   - Aptos localnet running: `aptos node run-local-testnet --with-faucet`
 *   - Contracts deployed on both sides (run deploy scripts first)
 *   - APTOS_MODULE_ADDR, APTOS_VAULT_ADDR, APTOS_BRIDGE_ADDR, APTOS_OPERATOR_KEY,
 *     ETH_RPC_URL, ETH_VAULT_OFT_ADDR, ETH_EXECUTOR_ADDR, ETH_ENDPOINT_ADDR
 *     set in environment (or .env file)
 *
 * What this tests that unit tests cannot:
 *   - The full cross-VM message relay (Aptos event → ETH call, ETH event → Aptos call)
 *   - Vault accounting updates correctly across the async round-trip
 *   - The TypeScript relay functions work against real localnet state
 */

import { describe, it, beforeAll } from "vitest";
import { expect } from "vitest";
import { ethers } from "ethers";
import { Aptos, Account, Ed25519PrivateKey } from "@aptos-labs/ts-sdk";
import {
  localnetClient,
  submitAndWait,
  getVaultState,
} from "./helpers/aptos.js";
import {
  encodePayload,
  decodeAction,
  relayAptosToEth,
  relayEthToAptos,
  hexToBytes,
  ACTION_DEPLOY,
  ACTION_RECALL,
  ACTION_COMPLETE,
} from "./helpers/relay.js";

// ── Config from environment ──────────────────────────────────────────────────

const MODULE_ADDR    = process.env.APTOS_MODULE_ADDR!;
const VAULT_ADDR     = process.env.APTOS_VAULT_ADDR!;
const BRIDGE_ADDR    = process.env.APTOS_BRIDGE_ADDR!;
const REGISTRY_ADDR  = process.env.APTOS_REGISTRY_ADDR!;
const OPERATOR_KEY   = process.env.APTOS_OPERATOR_KEY!;
const ETH_RPC        = process.env.ETH_RPC_URL ?? "http://127.0.0.1:8545";
const VAULT_OFT_ADDR = process.env.ETH_VAULT_OFT_ADDR!;
const EXECUTOR_ADDR  = process.env.ETH_EXECUTOR_ADDR!;
const ENDPOINT_ADDR  = process.env.ETH_ENDPOINT_ADDR!;

const STRATEGY_ID    = 0n;
const DEPLOY_AMOUNT  = 100_000_000n; // 1 APT in octas

// ── Minimal ABIs ─────────────────────────────────────────────────────────────

const VAULT_OFT_ABI = [
  "function trustedRemotes(uint16) view returns (bytes)",
  "function lzReceive(uint16,bytes,uint64,bytes) external",
];
const EXECUTOR_ABI = [
  "function deployedAmounts(uint64) view returns (uint256)",
  "function receivedCount() view returns (uint256)",
];
const ENDPOINT_ABI = [
  "function receivePayload(uint16,bytes,address,uint64,bytes) external",
  "function getOutboundNonce(uint16,address) view returns (uint64)",
];
// ── Setup ────────────────────────────────────────────────────────────────────

let aptosClient: Aptos;
let operator: Account;
let provider: ethers.JsonRpcProvider;
let signer: ethers.Wallet;
let vaultOFT: ethers.Contract;
let executor: ethers.Contract;
let endpoint: ethers.Contract;

// Trusted remote path for Aptos→ETH messages (set during contract deploy)
let trustedRemotePath: string;

beforeAll(async () => {
  // Aptos localnet
  aptosClient = localnetClient();
  operator = Account.fromPrivateKey({ privateKey: new Ed25519PrivateKey(OPERATOR_KEY) });

  // Ethereum local node (Hardhat or Anvil)
  provider = new ethers.JsonRpcProvider(ETH_RPC);
  signer   = new ethers.Wallet((await provider.listAccounts())[0] as any, provider);

  vaultOFT  = new ethers.Contract(VAULT_OFT_ADDR, VAULT_OFT_ABI, signer);
  executor  = new ethers.Contract(EXECUTOR_ADDR,  EXECUTOR_ABI, signer);
  endpoint  = new ethers.Contract(ENDPOINT_ADDR,  ENDPOINT_ABI, signer);

  // Read the trusted remote path VaultOFT expects for Aptos messages
  trustedRemotePath = await vaultOFT.trustedRemotes(108);
});

// ── Tests ────────────────────────────────────────────────────────────────────

describe("E2E bridge round-trip (Aptos localnet + ETH local node)", () => {

  it("deploy: operator sends capital cross-chain, Ethereum executor registers it", async () => {
    const stateBefore = await getVaultState(aptosClient, MODULE_ADDR, VAULT_ADDR);
    const nonce = 1;

    // Operator triggers deploy on Aptos (moves APT from idle → deployed)
    await submitAndWait(aptosClient, operator, {
      function: `${MODULE_ADDR}::yield_vault::deploy_to_strategy` as `${string}::${string}::${string}`,
      typeArguments: [],
      functionArguments: [VAULT_ADDR, REGISTRY_ADDR, STRATEGY_ID, DEPLOY_AMOUNT, 0],
    });

    const stateAfter = await getVaultState(aptosClient, MODULE_ADDR, VAULT_ADDR);
    expect(stateAfter.deployed_assets).to.equal(stateBefore.deployed_assets + DEPLOY_AMOUNT);
    expect(stateAfter.idle_assets).to.equal(stateBefore.idle_assets - DEPLOY_AMOUNT);

    // Relay the bridge_out payload to Ethereum
    const payload = encodePayload(ACTION_DEPLOY, DEPLOY_AMOUNT, STRATEGY_ID, BigInt(nonce), VAULT_ADDR.padStart(66, "0x").padStart(66, "0"));
    await relayAptosToEth(endpoint, vaultOFT, trustedRemotePath, payload, nonce);

    expect(await executor.deployedAmounts(STRATEGY_ID)).to.equal(DEPLOY_AMOUNT);
  });

  it("recall: executor sends COMPLETE back, vault accounting restored", async () => {
    // Pre-condition: capital is deployed (run deploy step first or seed state)
    const deployNonce = 1;
    const deployPayload = encodePayload(ACTION_DEPLOY, DEPLOY_AMOUNT, STRATEGY_ID, BigInt(deployNonce), VAULT_ADDR.padStart(66, "0x").padStart(66, "0"));
    await relayAptosToEth(endpoint, vaultOFT, trustedRemotePath, deployPayload, deployNonce);

    const stateBefore = await getVaultState(aptosClient, MODULE_ADDR, VAULT_ADDR);

    // Operator triggers recall on Aptos
    await submitAndWait(aptosClient, operator, {
      function: `${MODULE_ADDR}::yield_vault::recall_from_strategy` as `${string}::${string}::${string}`,
      typeArguments: [],
      functionArguments: [VAULT_ADDR, REGISTRY_ADDR, STRATEGY_ID, DEPLOY_AMOUNT, 0],
    });

    const recallNonce = 2;
    const recallPayload = encodePayload(ACTION_RECALL, DEPLOY_AMOUNT, STRATEGY_ID, BigInt(recallNonce), VAULT_ADDR.padStart(66, "0x").padStart(66, "0"));
    await relayAptosToEth(endpoint, vaultOFT, trustedRemotePath, recallPayload, recallNonce);

    // Ethereum executor sent COMPLETE back — read payload from event/FakeAptosReceiver
    // For localnet tests against a real Ethereum node, we read the last outbound packet
    // from the endpoint's emitted PacketSent event and relay it to Aptos.
    const filter = endpoint.filters?.PacketSent?.();
    const events = filter ? await endpoint.queryFilter(filter, -10) : [];
    expect(events.length).to.be.greaterThan(0);

    const completePayload = (events[events.length - 1] as any).args.payload as string;
    expect(decodeAction(completePayload)).to.equal(ACTION_COMPLETE);

    // Relay COMPLETE back to Aptos (credited via credit_bridge_return)
    const ethVaultOftTrustedBytes = Array.from(
      Buffer.from(VAULT_OFT_ADDR.replace("0x", "").padStart(64, "0"), "hex")
    ) as number[];
    await relayEthToAptos(
      aptosClient, operator, MODULE_ADDR, BRIDGE_ADDR,
      101, // ETH chain ID
      ethVaultOftTrustedBytes,
      hexToBytes(completePayload),
    );

    const stateAfter = await getVaultState(aptosClient, MODULE_ADDR, VAULT_ADDR);
    expect(stateAfter.idle_assets).to.equal(stateBefore.idle_assets + DEPLOY_AMOUNT);
    expect(stateAfter.deployed_assets).to.equal(stateBefore.deployed_assets - DEPLOY_AMOUNT);
  });

});
