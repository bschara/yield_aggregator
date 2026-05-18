# Offchain Layer

The offchain engine automates vault management. Every 30 seconds it reads on-chain state, runs the policy engines, and submits transactions if action is needed.

---

## Component Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                         main.ts (loop)                           │
│                                                                  │
│  ┌─────────────────────────────┐   ┌──────────────────────────┐  │
│  │          INDEXER            │   │        ANALYTICS         │  │
│  │                             │   │                          │  │
│  │  on_chain_listener.ts       │   │  apy_tracker.ts          │  │
│  │  ├─ readVaultResource()     │──▶│  ├─ update(events)       │  │
│  │  ├─ readRegistryStrategies()│   │  ├─ computeApy()         │  │
│  │  └─ pollHarvestEvents()     │   │  └─ buildApyMap()        │  │
│  │                             │   │                          │  │
│  │  position_tracker.ts        │   │  TVL ring buffer (30pts) │  │
│  │  └─ buildVaultState()       │   │  per-strategy yield log  │  │
│  │                             │   └──────────────────────────┘  │
│  │  eth_listener.ts            │                                  │
│  │  └─ syncEthEvents()         │                                  │
│  │  └─ getPendingBridges()     │                                  │
│  └─────────────────────────────┘                                  │
│                  │                                                │
│                  ▼                                                │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │              POLICY SERVER  (Python FastAPI)             │    │
│  │                                                          │    │
│  │  POST /decide ◀─── VaultState + pendingBridges          │    │
│  │                                                          │    │
│  │  rebalance_policy.py                                     │    │
│  │  ├─ yield_model.py  (Yield Engine)                       │    │
│  │  └─ risk_model.py   (Risk Engine)                        │    │
│  │                                                          │    │
│  │  returns: Action { type, strategyId, amountOctas }       │    │
│  └──────────────────────────────────────────────────────────┘    │
│                  │                                                │
│                  ▼                                                │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │                    ORCHESTRATOR                          │    │
│  │                                                          │    │
│  │  intent_builder.ts  ──▶  executor.ts                     │    │
│  │  buildDeployIntent()     ├─ calls entry fun by name      │    │
│  │  buildRecallIntent()     ├─ signs with operator key      │    │
│  │  buildHarvestIntent()    └─ submits Aptos transaction    │    │
│  └──────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────┘
```

---

## Indexer

### `indexer/on_chain_listener.ts`

Reads Aptos chain state using the Aptos SDK v2 (`@aptos-labs/ts-sdk`).

**Key functions:**

| Function                                   | Description                                                |
| ------------------------------------------ | ---------------------------------------------------------- |
| `readVaultResource(vaultAddr)`             | Returns raw `Vault` struct fields from chain               |
| `readRegistryResource(registryAddr)`       | Returns `Registry` with strategy table handle              |
| `readStrategyFromTable(handle, id)`        | Reads a single strategy from the registry table            |
| `readAllocationFromTable(handle, id)`      | Reads APT deployed to a strategy (octas)                   |
| `pollHarvestEvents(limit)`                 | Returns new `HarvestEvent`s since last poll (cursor-based) |
| `pollDeployEvents(limit)`                  | Returns new `DeployEvent`s since last poll                 |
| `fetchChainState(vaultAddr, registryAddr)` | Runs all of the above, returns `ChainSnapshot`             |

Cursors are in-memory. On restart, the engine re-reads from the last known event offset (offset 0 on first start — seeds APY data from full history).

### `indexer/position_tracker.ts`

Converts a `ChainSnapshot` into a typed `VaultState`:

```typescript
interface VaultState {
  tvl: number; // total_assets in APT
  idleAssets: number; // idle_assets in APT
  deployedAssets: number;
  utilization: number; // deployedAssets / tvl
  strategies: StrategyPosition[];
  snapshotTs: number;
}

interface StrategyPosition {
  strategyId: string;
  capitalAllocated: number; // APT
  maxExposure: number; // APT
  apy: number; // e.g. 0.05 = 5%
  riskScore: number; // 0–1
  lastHarvestTs: number; // unix seconds
}
```

`riskScore` = `exposureRatio × 0.6 + utilization × 0.4` (higher = riskier).

### `indexer/eth_listener.ts`

Polls `VaultOFT` events on Ethereum using ethers.js:

- `CrossChainReceive(ACTION_DEPLOY)` — a deploy message arrived on Ethereum (capital is there)
- `CrossChainSent(ACTION_COMPLETE)` — Ethereum sent capital back (removes from pending)

`getPendingBridgeMessages(timeoutSec)` returns messages that have been pending longer than `timeoutSec` — these are flagged by the Risk Engine as potential stuck-capital scenarios.

---

## Analytics Index

### `analytics/apy_tracker.ts`

**APY calculation:**

```
APY = (cumulativeYield / deployedApt) × (SECONDS_PER_YEAR / elapsed)
```

`cumulativeYield` is credited manually when the main loop observes `total_assets` increase after a harvest. `HarvestEvent` timestamps are used to track the yield window.

**TVL ring buffer:** last 30 snapshots of `(tvl, timestamp)` — useful for dashboards and trend detection.

**Key functions:**

| Function                                                           | Description                                               |
| ------------------------------------------------------------------ | --------------------------------------------------------- |
| `update(harvestEvents, deployEvents, deployedAmounts, tvl, nowTs)` | Called each tick; updates records and TVL buffer          |
| `creditYield(strategyId, yieldApt, ts)`                            | Manually credits observed yield to a strategy             |
| `buildApyMap(nowTs)`                                               | Returns `Map<strategyId, apy>` for all tracked strategies |
| `getLastHarvestTsMap()`                                            | Returns last harvest timestamp per strategy               |

---

## Policy Server (Python)

### `ai/risk_model.py` — Risk Engine

**Checks performed each `/decide` call:**

| Check                             | Threshold                             | Action triggered     |
| --------------------------------- | ------------------------------------- | -------------------- |
| Strategy over `max_exposure`      | > 100%                                | Recall excess        |
| Bridge message stale              | > `BRIDGE_TIMEOUT_SEC` (default 600s) | Recall that strategy |
| Vault utilisation warn            | > 80%                                 | `RiskLevel.MEDIUM`   |
| Vault utilisation critical        | > 90%                                 | `RiskLevel.HIGH`     |
| Any stale bridge or over-exposure | —                                     | `RiskLevel.CRITICAL` |

### `ai/yield_model.py` — Yield Engine

**Strategy scoring:**

```
score = APY × headroom × risk_discount
```

Where:

- `headroom = 1 - capitalAllocated / maxExposure`
- `risk_discount = 1 - riskScore × 0.5`

**Deploy target selection:** highest-scoring strategy that has headroom and `riskScore < 0.9`.

**Deploy amount:** `min(idle × 0.8, headroom)` — always keeps ≥20% idle.

**Harvest trigger:** `elapsed ≥ HARVEST_MIN_INTERVAL_SEC` (default 3600s = 1 hour).

**Underperformer recall:** any strategy with `0 < APY < 5%` is flagged for recall.

### `ai/rebalance_policy.py` — Decision Logic

Priority order for each tick:

```
1. Recall over-exposed strategy        (risk guard, highest priority)
2. Recall strategy with stale bridge   (stuck-capital guard)
3. Recall under-performing strategy    (APY < 5% threshold)
4. Deploy idle capital to best target  (yield maximisation)
5. Harvest mature strategy             (yield collection)
6. No-op                               (everything is fine)
```

Only one action is returned per tick. The loop re-evaluates on the next tick.

### `ai/server.py` — FastAPI Endpoint

```
POST /decide
  Content-Type: application/json
  Body: VaultState (see risk_model.py for schema)

Response:
  {
    "type": "harvest" | "deploy" | "recall" | "none",
    "strategyId": "0",
    "amountOctas": 500000000,
    "reason": "harvest strategy 0 (last=1716000000)"
  }

GET /health
  Response: { "status": "ok" }
```

---

## Orchestrator

### `orchestrator/intent_builder.ts`

Builds `ExecutionIntent` structs that match `strategy_engine.move`:

```typescript
// Action ordinals must match Move enum: Deposit=0, Withdraw=1, Harvest=2, Exit=3
buildDeployIntent(strategyId, amountOctas, feeOctas?)   → ExecutionIntent
buildRecallIntent(strategyId, amountOctas, feeOctas?)   → ExecutionIntent
buildHarvestIntent(strategyId, feeOctas?)               → ExecutionIntent
buildExitIntent(strategyId, amountOctas, feeOctas?)     → ExecutionIntent
```

Nonces are monotonically increasing from `Math.floor(Date.now() / 1000)` on startup.

### `orchestrator/executor.ts`

Calls `public entry fun` wrappers on-chain by qualified function name via the Aptos SDK v2 — no pre-compiled bytecode files required:

```typescript
aptos.transaction.build.simple({
  sender,
  data: { function: "<MODULE_ADDR>::eth_bridge_adapter::deploy_and_bridge_entry", functionArguments },
});
aptos.signAndSubmitTransaction({ signer: operatorAccount, transaction });
aptos.waitForTransaction({ transactionHash });
```

**Operator key** is loaded from `OPERATOR_PRIVATE_KEY` env var via `Account.fromPrivateKey(Ed25519PrivateKey)`.

**`MODULE_ADDR`** is read from `APTOS_MODULE_ADDR` env var.

**Function mapping:**

| Action  | Entry function                                    |
| ------- | ------------------------------------------------- |
| deploy  | `eth_bridge_adapter::deploy_and_bridge_entry`     |
| recall  | `eth_bridge_adapter::recall_and_send_entry`       |
| harvest | `eth_bridge_adapter::harvest_and_send_entry`      |
| exit    | `eth_bridge_adapter::recall_and_send_entry`       |

Each combined entry function atomically performs vault accounting and initiates the LayerZero bridge message in a single Aptos transaction.

---

## Configuration

All settings via environment variables (copy `offchain/.env.example` → `offchain/.env`):

| Variable                   | Default                    | Description                                       |
| -------------------------- | -------------------------- | ------------------------------------------------- |
| `APTOS_RPC`                | `http://localhost:8080/v1` | Aptos node RPC                                    |
| `APTOS_MODULE_ADDR`        | —                          | Deployed module address                           |
| `VAULT_ADDR`               | —                          | Vault resource account address                    |
| `REGISTRY_ADDR`            | —                          | Strategy registry address                         |
| `OPERATOR_PRIVATE_KEY`     | —                          | Ed25519 private key (hex)                         |
| `ETH_RPC`                  | `http://localhost:8545`    | Ethereum node RPC                                 |
| `VAULT_OFT_ADDR`           | —                          | VaultOFT contract address                         |
| `POLICY_SERVER_URL`        | `http://localhost:8001`    | Python policy server                              |
| `LOOP_INTERVAL_MS`         | `30000`                    | Loop cadence in milliseconds                      |
| `BRIDGE_TIMEOUT_SEC`       | `600`                      | Seconds before a bridge message is flagged stale  |
| `MIN_DEPLOY_AMOUNT`        | `100000000`                | Minimum idle APT (octas) before deploying (1 APT) |
| `HARVEST_MIN_INTERVAL_SEC` | `3600`                     | Minimum seconds between harvests                  |

---

## Running

```bash
make install-offchain

make start-policy
# → starts uvicorn on http://localhost:8001

# Terminal 2: start TypeScript main loop
make start-offchain
# → polls every 30s, logs each tick + action taken
```

On startup the main loop checks `/health` on the policy server and exits if it is unreachable.
