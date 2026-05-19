import { ethers } from "ethers";

const ETH_RPC = import.meta.env.VITE_ETH_RPC ?? "";
const VAULT_OFT_ADDR = import.meta.env.VITE_VAULT_OFT_ADDR ?? "";

const VAULT_OFT_ABI = [
  "event CrossChainReceive(uint8 action, uint64 amount, uint64 strategyId, uint64 nonce)",
  "event CrossChainSent(uint8 action, uint64 amount, uint64 strategyId, uint64 nonce)",
];

export interface BridgeEvent {
  type: "incoming" | "outgoing";
  action: number;
  amount: bigint;
  strategyId: bigint;
  nonce: bigint;
  blockNumber: number;
  txHash: string;
}

export async function fetchPendingBridges(): Promise<BridgeEvent[]> {
  if (!ETH_RPC || !VAULT_OFT_ADDR) return [];
  try {
    const provider = new ethers.JsonRpcProvider(ETH_RPC);
    const contract = new ethers.Contract(VAULT_OFT_ADDR, VAULT_OFT_ABI, provider);
    const currentBlock = await provider.getBlockNumber();
    const fromBlock = Math.max(0, currentBlock - 2000);

    const [inLogs, outLogs] = await Promise.all([
      contract.queryFilter(contract.filters.CrossChainReceive(), fromBlock),
      contract.queryFilter(contract.filters.CrossChainSent(), fromBlock),
    ]);

    const parse = (logs: ethers.EventLog[], type: "incoming" | "outgoing"): BridgeEvent[] =>
      logs.map((log) => ({
        type,
        action: Number(log.args[0]),
        amount: BigInt(log.args[1].toString()),
        strategyId: BigInt(log.args[2].toString()),
        nonce: BigInt(log.args[3].toString()),
        blockNumber: log.blockNumber,
        txHash: log.transactionHash,
      }));

    return [...parse(inLogs as ethers.EventLog[], "incoming"), ...parse(outLogs as ethers.EventLog[], "outgoing")].sort(
      (a, b) => b.blockNumber - a.blockNumber
    );
  } catch {
    return [];
  }
}
