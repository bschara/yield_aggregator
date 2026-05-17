import { ethers } from "ethers";
import { Aptos, Account } from "@aptos-labs/ts-sdk";
import { submitAndWait } from "./aptos.js";

// Payload constants — must match oft_bridge.move and VaultOFT.sol
export const ACTION_DEPLOY   = 0x01;
export const ACTION_RECALL   = 0x02;
export const ACTION_HARVEST  = 0x03;
export const ACTION_COMPLETE = 0x04;

// Encode the 57-byte cross-chain payload (matches both VMs)
export function encodePayload(
  action: number,
  amount: bigint,
  strategyId: bigint,
  nonce: bigint,
  vaultAddr: string,   // 32-byte hex
): string {
  return ethers.solidityPacked(
    ["uint8", "uint64", "uint64", "uint64", "bytes32"],
    [action, amount, strategyId, nonce, vaultAddr],
  );
}

export function decodeAction(payload: string): number {
  return parseInt(payload.slice(2, 4), 16);
}

// ── Aptos → Ethereum relay ───────────────────────────────────────────────────
//
// Simulates the LZ executor delivering an Aptos→ETH message.
// In production: the LZ executor monitors Aptos events and calls vaultOFT.lzReceive.
// Here: test captures the payload from Aptos bridge events and passes it here.
//
// trustedRemotePath must equal vaultOFT.trustedRemotes[108] (set during deploy).
export async function relayAptosToEth(
  ethEndpoint: ethers.Contract,
  vaultOFT: ethers.Contract,
  trustedRemotePath: string,
  payload: string,
  nonce: number,
): Promise<void> {
  const APTOS_CHAIN_ID = 108;
  await ethEndpoint.receivePayload(
    APTOS_CHAIN_ID,
    trustedRemotePath,
    await vaultOFT.getAddress(),
    nonce,
    payload,
  );
}

// ── Ethereum → Aptos relay ───────────────────────────────────────────────────
//
// After the Ethereum executor sends a COMPLETE message, the LZ executor would
// normally deliver it to oft_bridge::lz_receive on Aptos.
// Here: test reads the payload from FakeAptosReceiver.lastMessage() and submits
// it to the Aptos localnet via lz_receive_for_test (bypasses LZ queue).
//
// srcAddress: the trusted remote bytes (32-byte ETH address registered on Aptos side)
export async function relayEthToAptos(
  aptosClient: Aptos,
  operator: Account,
  moduleAddr: string,
  bridgeAddr: string,
  srcChainId: number,
  srcAddress: number[],   // trusted remote as byte array
  payload: number[],      // payload byte array
): Promise<void> {
  await submitAndWait(aptosClient, operator, {
    function: `${moduleAddr}::oft_bridge::lz_receive_for_test` as `${string}::${string}::${string}`,
    typeArguments: [],
    functionArguments: [bridgeAddr, srcChainId, srcAddress, payload],
  });
}

// Convert a hex string to a byte array (for Move vector<u8> args)
export function hexToBytes(hex: string): number[] {
  const clean = hex.startsWith("0x") ? hex.slice(2) : hex;
  const bytes: number[] = [];
  for (let i = 0; i < clean.length; i += 2) {
    bytes.push(parseInt(clean.slice(i, i + 2), 16));
  }
  return bytes;
}
