import "dotenv/config";
import { fetchChainState } from "./indexer/on_chain_listener.js";
import { buildVaultState } from "./indexer/position_tracker.js";
import {
  initEthListener,
  syncEthEvents,
  getAllPending,
} from "./indexer/eth_listener.js";
import {
  update as updateApy,
  buildApyMap,
  getLastHarvestTsMap,
} from "./analytics/apy_tracker.js";
import {
  buildDeployIntent,
  buildRecallIntent,
  buildHarvestIntent,
} from "./orchestrator/intent_builder.js";
import { executeIntent } from "./orchestrator/executor.js";

const VAULT_ADDR = process.env.VAULT_ADDR!;
const REGISTRY_ADDR = process.env.REGISTRY_ADDR!;
const ENGINE_ADDR = process.env.ENGINE_ADDR!;
const VAULT_OFT_ADDR = process.env.VAULT_OFT_ADDR!;
const ETH_RPC = process.env.ETH_RPC!;
const POLICY_URL = process.env.POLICY_SERVER_URL ?? "http://localhost:8001";
const LOOP_MS = parseInt(process.env.LOOP_INTERVAL_MS ?? "30000");
const BRIDGE_TIMEOUT = parseInt(process.env.BRIDGE_TIMEOUT_SEC ?? "600");

async function callPolicy(
  body: object
): Promise<{
  type: string;
  strategyId?: string;
  amountOctas?: number;
  reason: string;
}> {
  const res = await fetch(`${POLICY_URL}/decide`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok)
    throw new Error(`policy server ${res.status}: ${await res.text()}`);
  return res.json();
}

async function tick(): Promise<void> {
  const now = Math.floor(Date.now() / 1000);
  console.log(`\n[main] tick at ${new Date().toISOString()}`);

  // 1. Index on-chain state
  const snapshot = await fetchChainState(VAULT_ADDR, REGISTRY_ADDR);

  // 2. Sync Ethereum bridge events
  await syncEthEvents();
  const pendingBridges = getAllPending();

  // 3. Update analytics
  const deployedAmounts = new Map<number, bigint>();
  for (const s of snapshot.strategies) {
    //deployedAmounts populated from vault allocations table in position_tracker
  }
  updateApy(
    snapshot.harvestEvents,
    snapshot.deployEvents,
    deployedAmounts,
    Number(snapshot.vault.total_assets) / 1e8,
    now
  );
  const apyMap = buildApyMap(now);
  const lastHarvestTsMap = getLastHarvestTsMap();

  // 4. Build enriched vault state
  const vaultState = await buildVaultState(snapshot, apyMap, lastHarvestTsMap);

  console.log(
    `[main] TVL=${vaultState.tvl.toFixed(4)} APT  ` +
      `idle=${vaultState.idleAssets.toFixed(4)} APT  ` +
      `util=${(vaultState.utilization * 100).toFixed(1)}%  ` +
      `strategies=${vaultState.strategies.length}  ` +
      `pendingBridges=${pendingBridges.length}`
  );

  // 5. Ask policy server for action
  const payload = { ...vaultState, pendingBridges };
  const action = await callPolicy(payload);
  console.log(`[main] policy decision: ${action.type} — ${action.reason}`);

  if (action.type === "none" || !action.strategyId) return;

  // 6. Build and submit intent
  const strategyId = parseInt(action.strategyId);
  const amount = action.amountOctas ?? 0;

  let intent;
  if (action.type === "deploy") {
    intent = buildDeployIntent(strategyId, amount);
  } else if (action.type === "recall") {
    intent = buildRecallIntent(strategyId, amount);
  } else if (action.type === "harvest") {
    intent = buildHarvestIntent(strategyId);
  } else {
    console.warn(`[main] unknown action type: ${action.type}`);
    return;
  }

  const result = await executeIntent(intent, VAULT_ADDR, REGISTRY_ADDR);
  if (result.success) {
    console.log(`[main] submitted ${result.action} tx=${result.txHash}`);
  } else {
    console.error(`[main] execution failed: ${result.error}`);
  }
}

async function main(): Promise<void> {
  console.log("[main] yield aggregator offchain engine starting");
  console.log(
    `[main] vault=${VAULT_ADDR} registry=${REGISTRY_ADDR} engine=${ENGINE_ADDR}`
  );
  console.log(
    `[main] loop interval=${LOOP_MS}ms  bridge timeout=${BRIDGE_TIMEOUT}s`
  );

  initEthListener(ETH_RPC, VAULT_OFT_ADDR);

  // Check policy server is reachable before entering the loop
  try {
    const health = await fetch(`${POLICY_URL}/health`);
    if (!health.ok) throw new Error(`HTTP ${health.status}`);
    console.log("[main] policy server healthy");
  } catch (err) {
    console.error(
      `[main] policy server not reachable at ${POLICY_URL}: ${err}`
    );
    console.error(
      "[main] start it with: python3 -m uvicorn ai.server:app --port 8001"
    );
    process.exit(1);
  }

  while (true) {
    try {
      await tick();
    } catch (err) {
      console.error(`[main] tick error: ${err}`);
    }
    await new Promise((resolve) => setTimeout(resolve, LOOP_MS));
  }
}

main();
