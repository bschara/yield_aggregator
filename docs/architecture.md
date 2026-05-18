# Architecture

## Overview

The aggregator connects Aptos and Ethereum via a custom LayerZero V1 bridge. Users deposit APT into a vault on Aptos; an offchain engine decides when and where to deploy that capital (currently Ethereum-based strategies, with Aptos-native lending planned). Yield flows back automatically via the same bridge.

---

## Component Map

```
┌─────────────────────────────────────────────────────────────┐
│                        APTOS CHAIN                          │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                     yield_vault                     │   │
│  │  total_assets  idle_assets  deployed_assets         │   │
│  │  allocations: Table<strategy_id, amount>            │   │
│  └────────┬──────────────────────────────┬────────────┘   │
│           │ deploy_to_strategy            │ credit_bridge_* │
│           ▼                              ▲                  │
│  ┌─────────────────┐         ┌──────────────────────────┐  │
│  │strategy_registry│         │     message_receiver     │  │
│  │ Strategy{adapter│         │ handle_incoming(action)  │  │
│  │  max_exposure   │         └──────────┬───────────────┘  │
│  │  risk_level}    │                    │                   │
│  └─────────────────┘         ┌──────────▼───────────────┐  │
│           │                  │       oft_bridge          │  │
│  ┌────────▼────────┐         │  lock APT on send         │  │
│  │adapter_interface│         │  unlock APT on receive    │  │
│  │ dispatch layer  │         │  lz_receive / bridge_out  │  │
│  └────────┬────────┘         └──────────┬───────────────┘  │
│           │                             │  LayerZero V1     │
│  ┌────────▼────────┐                    │                   │
│  │ eth_bridge_     │────────────────────┘                   │
│  │ adapter         │  bridge_out / send_recall /            │
│  │ (async)         │  send_harvest                          │
│  └─────────────────┘                                        │
│                                                             │
│  ┌────────────────────────────────────────┐                 │
│  │ lending_adapter  (STUBBED)             │                 │
│  │ Aries / Echelon / Thala integration    │                 │
│  └────────────────────────────────────────┘                 │
└─────────────────────────────────────────────────────────────┘
                          │  LayerZero message (57-byte payload)
┌─────────────────────────▼───────────────────────────────────┐
│                      ETHEREUM CHAIN                         │
│                                                             │
│  ┌──────────────────────┐    ┌────────────────────────────┐ │
│  │      VaultOFT        │───▶│    EthStrategyExecutor     │ │
│  │  ERC-20 wAPT token   │    │  _deploy  (STUBBED → Aave) │ │
│  │  LayerZero endpoint  │◀───│  _recall  (STUBBED → Aave) │ │
│  │  mint / burn wAPT    │    │  _harvest (STUBBED → Aave) │ │
│  └──────────────────────┘    └────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                          ▲
┌─────────────────────────┼───────────────────────────────────┐
│                   OFFCHAIN LAYER                            │
│                                                             │
│  ┌───────────────────┐  ┌──────────────┐  ┌─────────────┐  │
│  │     Indexer       │  │  Analytics   │  │  Policy     │  │
│  │ on_chain_listener │─▶│  apy_tracker │─▶│  (FastAPI)  │  │
│  │ position_tracker  │  │  TVL history │  │  /decide    │  │
│  │ eth_listener      │  └──────────────┘  └──────┬──────┘  │
│  └───────────────────┘                           │         │
│                                          ┌────────▼──────┐  │
│                                          │ Orchestrator  │  │
│                                          │intent_builder │  │
│                                          │   executor    │  │
│                                          └───────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## Cross-Chain Data Flow

### Deploy (Aptos → Ethereum)

```
1. Operator calls deploy_to_strategy(vault, registry, strategy_id, amount)
   └─ vault: idle_assets -= amount, deployed_assets += amount
   └─ eth_bridge_adapter.bridge_out() invoked via adapter_interface

2. eth_bridge_adapter encodes 57-byte payload:
   [ACTION_DEPLOY | amount | strategy_id | nonce | vault_addr]

3. oft_bridge.bridge_out():
   └─ APT locked in OFT state (VaultBridgeOFT coin store)
   └─ LayerZero send to Ethereum (chain_id = 101)

4. Ethereum: VaultOFT.lzReceive()
   └─ validates trusted remote
   └─ mints wAPT to EthStrategyExecutor
   └─ calls executeIncoming(amount, payload)

5. EthStrategyExecutor._deploy():
   └─ TODO: swap wAPT → USDC via DEX
   └─ TODO: deposit USDC into Aave V3
   └─ currently: tracks deployedAmounts[strategyId] += amount
```

### Recall (Ethereum → Aptos)

```
1. Offchain sends ACTION_RECALL signal to Ethereum via send_recall()
   └─ zero-coin LayerZero message to EthStrategyExecutor

2. EthStrategyExecutor._recall():
   └─ TODO: withdraw from Aave, swap USDC → wAPT
   └─ currently: burns wAPT, calls _sendBackToAptos()

3. _sendBackToAptos(): encodes ACTION_COMPLETE payload, calls lzSend()

4. Aptos: oft_bridge.lz_receive()
   └─ unlocks APT from OFT state
   └─ calls message_receiver.handle_incoming(ACTION_COMPLETE)

5. message_receiver → vault.credit_bridge_return()
   └─ deployed_assets -= amount, idle_assets += amount
```

### Harvest (yield collection)

```
Same as Recall but with ACTION_HARVEST / ACTION_COMPLETE sequence.
vault.credit_bridge_harvest() increases both total_assets and idle_assets
(unlike recall which only moves between deployed ↔ idle).
```

---

## Bridge Payload Format

All cross-chain messages use a fixed 57-byte payload (big-endian):

```
Offset  Size  Type      Field
──────  ────  ────────  ─────────────────────────────────────
0       1     uint8     action
                          0x01 = ACTION_DEPLOY
                          0x02 = ACTION_RECALL
                          0x03 = ACTION_HARVEST
                          0x04 = ACTION_COMPLETE
1       8     uint64    amount  (APT octas)
9       8     uint64    strategy_id
17      8     uint64    nonce  (replay protection)
25      32    bytes32   vault_addr  (Aptos address, zero-padded)
```

Encoding is implemented in both `oft_bridge.move` and `VaultOFT.sol` — they must stay in sync.

---

## Adapter Model

Adapters are registered with `adapter_registry` and dispatched through `adapter_interface`. Two adapter types exist:

| Type | Constant | Behaviour |
|------|----------|-----------|
| `TYPE_LENDING = 2` | sync | vault accounting updates immediately on dispatch |
| `TYPE_ETH_BRIDGE = 1` | async | vault accounting deferred until cross-chain COMPLETE message arrives |

Async adapters bypass the normal `adapter_interface` dispatch to avoid circular module dependencies (`vault → interface → eth_bridge → oft_bridge → message_receiver → vault`). The bridge adapter is invoked directly via scripts.

---

## Key Design Decisions

**Why lock APT instead of burn/mint on Aptos?**
APT is the Aptos native coin and cannot be burned by a third-party module. The bridge locks APT in the OFT module's coin store and mints wAPT (a regular ERC-20) on Ethereum. 1:1 parity is maintained as long as no slashing or loss occurs.

**Why custom payload instead of standard OFT wire format?**
The standard LayerZero OFT format carries only `amount` and `receiver`. The aggregator needs `action`, `strategy_id`, and `nonce` in every message, requiring a custom 57-byte payload on both sides.

**Why `public fun` rather than `public entry fun` for vault operations?**
Strategy operations (deploy, recall, harvest) are designed to be called from Move scripts, not directly from transactions. This enforces that they always go through the operator-gated `strategy_engine::execute_intent` with nonce replay protection. The offchain executor submits pre-compiled Move script bytecodes.

---

## LayerZero Chain IDs

| Chain | LZ Chain ID |
|-------|-------------|
| Aptos | 108 |
| Ethereum mainnet | 101 |
| Ethereum Sepolia | 10161 |
