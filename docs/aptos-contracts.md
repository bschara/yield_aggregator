# Aptos Contracts

All contracts live in `aptos/sources/` under the `YieldAggregator` named address. Module names match file names.

---

## yield_vault

`sources/vault/vault.move`

The central asset manager. Holds user capital, tracks share ownership, and coordinates strategy deployment.

### Structs

```move
struct Vault has key {
    total_assets: u128,
    total_shares: u128,
    idle_assets: u128,
    deployed_assets: u128,
    management_fee_bps: u64,
    performance_fee_bps: u64,
    allocations: Table<u64, u128>,
    owner: address,
    operator: address,
    paused: bool,
    signer_cap: SignerCapability,
}

struct DepositShares has key {
    deposit_amount: u64,
    deposit_time: u64,
    shares: u64,
    creator: address,
    transferRef: TransferRef,
    deleteRef: DeleteRef,
}
```

### Public API

| Function                                                                                    | Caller           | Description                                                                      |
| ------------------------------------------------------------------------------------------- | ---------------- | -------------------------------------------------------------------------------- |
| `init(account)`                                                                             | Owner            | Creates the vault resource account. Call once.                                   |
| `deposit(account, amount, vault_addr) → address`                                            | Anyone           | Deposits APT, mints proportional shares, returns `DepositShares` object address. |
| `deposit_entry(account, amount, vault_addr)`                                                | Anyone           | Entry-function wrapper around `deposit`.                                         |
| `withdraw(account, deposit_obj_addr, vault_addr)`                                           | Depositor        | Burns shares, returns APT. Requires sufficient `idle_assets`.                    |
| `deploy_to_strategy(account, vault_addr, registry_addr, strategy_id, amount, fee_amount)`   | Operator         | Moves APT from idle to strategy adapter.                                         |
| `recall_from_strategy(account, vault_addr, registry_addr, strategy_id, amount, fee_amount)` | Operator         | Requests APT back from strategy. Async for bridge adapters.                      |
| `harvest_strategy(account, vault_addr, registry_addr, strategy_id, fee_amount)`             | Operator         | Triggers yield collection on a strategy.                                         |
| `set_operator(account, vault_addr, new_operator)`                                           | Owner            | Transfers operator role.                                                         |
| `credit_bridge_return(vault_addr, strategy_id, amount)`                                     | message_receiver | Credits returned capital after cross-chain COMPLETE.                             |
| `credit_bridge_harvest(vault_addr, yield_amount)`                                           | message_receiver | Credits harvested yield, increases total_assets.                                 |
| `vault_address(owner) → address`                                                            | Any              | Derives deterministic vault address.                                             |

### Share Pricing

On first deposit: 1 share = 1 octa (1:1).
On subsequent deposits: `shares_minted = deposit_amount × total_shares / total_assets`.
On withdraw: `coins_out = shares × total_assets / total_shares`.

### Events

| Event            | Fields                                          | Emitted on             |
| ---------------- | ----------------------------------------------- | ---------------------- |
| `InitVaultEvent` | owner, vault_addr, init_time                    | `init`                 |
| `DepositEvent`   | depositor, deposit_time, shares, deposit_amount | `deposit`              |
| `WithdrawEvent`  | withdrawer, withdraw_time, shares, coins_out    | `withdraw`             |
| `DeployEvent`    | strategy_id, amount, timestamp                  | `deploy_to_strategy`   |
| `RecallEvent`    | strategy_id, amount, timestamp                  | `recall_from_strategy` |
| `HarvestEvent`   | strategy_id, timestamp                          | `harvest_strategy`     |

---

## strategy_registry

`sources/strategy/strategy_registry.move`

Stores metadata for each registered strategy. Only the registry owner can write.

### Structs

```move
struct Strategy has store {
    adapter: address,
    max_exposure: u64,
    risk: RiskLevel,
    active: bool,
    version: u64,
}

enum RiskLevel { Low, Medium, High }
```

### Public API

| Function                                                                        | Description                               |
| ------------------------------------------------------------------------------- | ----------------------------------------- |
| `init(account)`                                                                 | Creates registry owned by caller.         |
| `add_strategy(account, registry_addr, adapter, max_exposure, risk) → u64`       | Registers a new strategy, returns its ID. |
| `update_strategy(account, registry_addr, id, adapter?, max_exposure?, active?)` | Partial update via `Option` fields.       |
| `remove_strategy(account, registry_addr, id)`                                   | Soft-deletes (sets `active = false`).     |
| `is_active(registry_addr, id) → bool`                                           |                                           |
| `get_adapter(registry_addr, id) → address`                                      |                                           |
| `get_max_exposure(registry_addr, id) → u64`                                     |                                           |
| `strategy_exists(registry_addr, id) → bool`                                     |                                           |

---

## strategy_executor

`sources/strategy/strategy_engine.move`

Operator-gated intent execution with nonce-based replay protection.

### Structs

```move
enum ExecutionActionType { Deposit, Withdraw, Harvest, Exit }

struct ExecutionIntent has copy, drop, store {
    strategy_id: u64,
    action: ExecutionActionType,
    amount: u64,
    fee_amount: u64,
    target_chain: Option<u64>,
    nonce: u64,
}
```

### Public API

| Function                                                                  | Description                                  |
| ------------------------------------------------------------------------- | -------------------------------------------- |
| `init(account)`                                                           | Creates `ExecutionState` owned by caller.    |
| `set_operator(account, new_operator)`                                     | Transfers operator.                          |
| `execute_intent(account, engine_addr, vault_addr, registry_addr, intent)` | Validates operator + nonce, routes to vault. |

**Routing**: `Deposit → deploy_to_strategy`, `Withdraw/Exit → recall_from_strategy`, `Harvest → harvest_strategy`.

> `execute_intent` is `public fun`, not `public entry fun`. Call it via a compiled Move script, not directly from a transaction.

---

## adapter_interface

`sources/adapters/adapter_interface.move`

Thin dispatch layer. Looks up the adapter type from `adapter_registry` and routes to the correct implementation.

| Function                                     | Routes to                                 |
| -------------------------------------------- | ----------------------------------------- |
| `deposit(adapter_addr, amount, fee_amount)`  | `lending_adapter::trigger_deposit`        |
| `withdraw(adapter_addr, amount, fee_amount)` | `lending_adapter::trigger_withdraw`       |
| `harvest(adapter_addr, fee_amount)`          | `lending_adapter::trigger_harvest`        |
| `emergency_exit(adapter_addr, fee_amount)`   | `lending_adapter::trigger_emergency_exit` |

`eth_bridge_adapter` is intentionally excluded from this dispatch to avoid circular module dependencies. It is invoked directly by scripts.

---

## adapter_registry

`sources/adapters/adapter_registry.move`

Registration marker. Each adapter calls `register_adapter` on init.

```
TYPE_ETH_BRIDGE = 1  (async)
TYPE_LENDING    = 2  (sync)
```

Async adapters skip immediate vault accounting — updates arrive via `credit_bridge_*` callbacks.

---

## lending_adapter

`sources/adapters/lending_adapter.move`

**Status: All functions stubbed.**

Intended for Aptos-native lending protocol integration (Aries, Echelon, Thala). Currently a skeleton — all four trigger functions are empty TODOs.

---

## eth_bridge_adapter

`sources/adapters/eth_bridge_adapter.move`

Async adapter that bridges capital to Ethereum via LayerZero.

### Key State

```move
struct EthAdapter has key {
    owner: address,
    signer_cap: SignerCapability,
    bridge_cap: BridgeCapability,
    vault_addr: address,
    bridge_addr: address,
    dst_chain_id: u64,
    dst_vault_oft: vector<u8>,
    strategy_id: u64,
    deployed: u128,
    nonce: u64,
}
```

### Public API

| Function                                                                                       | Description                                                    |
| ---------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| `init(account, vault_addr, bridge_addr, dst_chain_id, dst_vault_oft, strategy_id, bridge_cap)` | Sets up adapter, registers as async with adapter_registry.     |
| `bridge_out(account, adapter_addr, amount, fee_amount)`                                        | Sends APT to Ethereum via LayerZero (ACTION_DEPLOY).           |
| `send_recall(account, adapter_addr, amount, fee_amount)`                                       | Signals Ethereum to withdraw (ACTION_RECALL, zero-coin).       |
| `send_harvest(account, adapter_addr, fee_amount)`                                              | Signals Ethereum to harvest yield (ACTION_HARVEST, zero-coin). |
| `trigger_emergency_exit(adapter_addr, fee_amount)`                                             | **Stubbed.**                                                   |

---

## oft_bridge

`sources/cross_chain/oft_bridge.move`

LayerZero V1 OFT bridge. Locks APT on send, unlocks on receive.

### Public API

| Function                                                                                                   | Description                                                                                                                 |
| ---------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `init(account, shared_decimals) → BridgeCapability`                                                        | Registers with LayerZero, returns capability to eth_bridge_adapter.                                                         |
| `set_trusted_remote(account, bridge_addr, chain_id, remote_addr)`                                          | Whitelists a 32-byte Ethereum OFT address. Must be called before any messages can be received.                              |
| `bridge_out(cap, bridge_addr, apt_coins, dst_chain_id, dst_receiver, payload, native_fee, adapter_params)` | Locks APT, sends LZ message with custom payload.                                                                            |
| `lz_receive(src_chain_id, src_address, payload, bridge_addr)`                                              | Production entry point called by LayerZero executor. Validates trusted remote, unlocks APT, dispatches to message_receiver. |
| `encode_payload(action, amount, strategy_id, nonce, vault_addr) → vector<u8>`                              | Produces the 57-byte wire format.                                                                                           |

---

## message_receiver

`sources/cross_chain/message_receiver.move`

Dispatches incoming cross-chain messages to vault accounting.

```
ACTION_COMPLETE (4) → vault::credit_bridge_return(vault_addr, strategy_id, amount)
ACTION_HARVEST  (3) → vault::credit_bridge_harvest(vault_addr, yield_amount)
```

Called by `oft_bridge::lz_receive_impl` after APT is unlocked and nonce is deduplicated.

---

## Scripts

Pre-written Move scripts that atomically combine multiple module calls.

| Script                   | What it does                                                             |
| ------------------------ | ------------------------------------------------------------------------ |
| `deploy_and_bridge.move` | Calls `execute_intent(Deposit)` then `eth_bridge_adapter.bridge_out()`   |
| `harvest_and_send.move`  | Calls `execute_intent(Harvest)` then `eth_bridge_adapter.send_harvest()` |
| `recall_and_send.move`   | Calls `execute_intent(Withdraw)` then `eth_bridge_adapter.send_recall()` |

The offchain executor loads compiled bytecodes (`.mv`) from `aptos/build/yield_aggregator/bytecode_scripts/` and submits them as script transactions.
