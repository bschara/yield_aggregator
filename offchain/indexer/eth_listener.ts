import { ethers } from "ethers";

// Minimal ABI — only the events we care about
const VAULT_OFT_ABI = [
  "event CrossChainReceive(uint16 indexed srcChainId, uint8 action, uint256 amount, uint64 nonce)",
  "event CrossChainSent(uint16 indexed dstChainId, uint8 action, uint256 amount, uint64 nonce)",
];

const ACTION_DEPLOY = 0x01;
const ACTION_COMPLETE = 0x04;

export interface PendingBridgeMessage {
  strategyId: string; // derived from nonce tracking (deploy nonce → strategy mapping)
  nonce: number;
  sentAt: number;   // unix seconds (block timestamp approximation)
  amount: number;   // in wAPT (same unit as octas)
}

// nonce → { sentAt, amount } for deploys that haven't received COMPLETE yet
const pendingDeploys = new Map<number, { sentAt: number; amount: bigint }>();

// nonces for which COMPLETE has been received
const completedNonces = new Set<number>();

let provider: ethers.JsonRpcProvider | null = null;
let contract: ethers.Contract | null = null;
let lastScannedBlock = 0;

export function initEthListener(rpcUrl: string, vaultOftAddr: string) {
  provider = new ethers.JsonRpcProvider(rpcUrl);
  contract = new ethers.Contract(vaultOftAddr, VAULT_OFT_ABI, provider);
}

export async function syncEthEvents(): Promise<void> {
  if (!provider || !contract) return;

  const latest = await provider.getBlockNumber();
  if (lastScannedBlock === 0) lastScannedBlock = Math.max(0, latest - 1000);

  const receiveFilter = contract.filters.CrossChainReceive();
  const sentFilter = contract.filters.CrossChainSent();

  const [receiveEvents, sentEvents] = await Promise.all([
    contract.queryFilter(receiveFilter, lastScannedBlock, latest),
    contract.queryFilter(sentFilter, lastScannedBlock, latest),
  ]);

  const block = await provider.getBlock(latest);
  const nowTs = block?.timestamp ?? Math.floor(Date.now() / 1000);

  for (const ev of receiveEvents as ethers.EventLog[]) {
    const action = Number(ev.args[1]);
    const amount = ev.args[2] as bigint;
    const nonce = Number(ev.args[3]);
    if (action === ACTION_DEPLOY && !completedNonces.has(nonce)) {
      pendingDeploys.set(nonce, { sentAt: nowTs, amount });
    }
  }

  for (const ev of sentEvents as ethers.EventLog[]) {
    const action = Number(ev.args[1]);
    const nonce = Number(ev.args[3]);
    if (action === ACTION_COMPLETE) {
      completedNonces.add(nonce);
      pendingDeploys.delete(nonce);
    }
  }

  lastScannedBlock = latest + 1;
}

export function getPendingBridgeMessages(timeoutSec: number): PendingBridgeMessage[] {
  const cutoff = Math.floor(Date.now() / 1000) - timeoutSec;
  const stale: PendingBridgeMessage[] = [];

  for (const [nonce, { sentAt, amount }] of pendingDeploys) {
    if (sentAt < cutoff) {
      stale.push({
        strategyId: "unknown", // refined by caller if nonce→strategyId mapping is available
        nonce,
        sentAt,
        amount: Number(amount),
      });
    }
  }

  return stale;
}

export function getAllPending(): PendingBridgeMessage[] {
  return Array.from(pendingDeploys.entries()).map(([nonce, { sentAt, amount }]) => ({
    strategyId: "unknown",
    nonce,
    sentAt,
    amount: Number(amount),
  }));
}
