# Cross-Platform Yield Aggregator

A cross-chain DeFi yield aggregator that lets users deposit APT on Aptos and earn yield from strategies running on Ethereum (Aave, etc.) and Aptos-native lending protocols. Capital flows cross-chain via a custom LayerZero V1 OFT bridge with a 57-byte payload protocol.

The architecture is designed for multi-chain expansion — Ethereum is the first external chain supported, with Solana, Polygon, Arbitrum, and others planned as additional strategy targets via new chain adapters.

## Architecture Overview

```
                         USER
                          │  deposit / withdraw APT
                          ▼
          ┌───────────────────────────────────────┐
          │              APTOS CHAIN              │
          │                                       │
          │  ┌──────────┐  deploy   ┌──────────┐ │
          │  │  Vault   │──────────▶│ETH Bridge│ │
          │  │          │◀──────────│ Adapter  │ │
          │  │idle_assets│  recall  └─────┬────┘ │
          │  │deployed   │                │      │
          │  └──────────┘                 │      │
          │       ▲  credit_bridge_*      │      │
          │       │                  OFT Bridge  │
          │       │               (lock/unlock)  │
          └───────┼───────────────────────┼──────┘
                  │                       │  LayerZero message
                  │      ┌────────────────▼──────────────┐
                  │      │        ETHEREUM CHAIN          │
                  │      │                                │
                  │      │  ┌──────────┐  ┌───────────┐  │
                  │      │  │ VaultOFT │─▶│ Strategy  │  │
                  │      │  │  (wAPT)  │  │ Executor  │  │
                  │      │  └──────────┘  │(Aave/DEX) │  │
                  │      │                └───────────┘  │
                  │      └────────────────────────────────┘
                  │
                  │           OFFCHAIN LAYER
                  │  ┌──────────────────────────────────────┐
                  │  │ Indexer → Analytics → Policy Server  │
                  └──│              ↓                        │
                     │        Orchestrator → Executor        │
                     └──────────────────────────────────────┘
```

## Repository Structure

```
cross_platform_yield_aggregator/
├── aptos/              Move smart contracts (vault, bridge, strategies)
├── ethereum/           Solidity contracts (VaultOFT, EthStrategyExecutor)
├── e2e-tests/          Cross-chain round-trip integration tests
├── offchain/           Yield Engine, Risk Engine, Analytics, Orchestrator
└── Makefile            Top-level build and run commands
```

## Quick Start

### Prerequisites

- [Aptos CLI](https://aptos.dev/tools/aptos-cli/) ≥ 4.x
- Node.js ≥ 20
- Python ≥ 3.11
- [Foundry](https://book.getfoundry.sh/) or Hardhat (installed via npm)

### 1. Install dependencies

```bash
make install-offchain
cd ethereum && npm install
cd e2e-tests && npm install
```

### 2. Run tests

```bash
make test
make test-e2e
```

### 3. Deploy and run

```bash
cd aptos && aptos move deploy --named-addresses YieldAggregator=<your_addr>

cd ethereum && npx hardhat run scripts/deploy.ts --network sepolia

cp offchain/.env.example offchain/.env
make start-policy
make start-offchain
```

## Documentation

| Doc                                              | Description                                             |
| ------------------------------------------------ | ------------------------------------------------------- |
| [Architecture](docs/architecture.md)             | Cross-chain data flow, component design, payload format |
| [Aptos Contracts](docs/aptos-contracts.md)       | Vault, strategy registry, adapters, OFT bridge API      |
| [Ethereum Contracts](docs/ethereum-contracts.md) | VaultOFT, EthStrategyExecutor API                       |
| [Offchain Layer](docs/offchain.md)               | Yield Engine, Risk Engine, Analytics, Orchestrator      |
| [Deployment Guide](docs/deployment.md)           | Step-by-step testnet and mainnet deployment             |
| [E2E Testing](docs/e2e-testing.md)               | Running and extending the bridge test suite             |

## Planned Chain Support

The bridge adapter model is designed so each new chain requires only a new adapter module on Aptos and a corresponding strategy executor contract on the target chain — the vault, registry, and OFT bridge core are chain-agnostic.

| Chain          | Status             | Strategy Target          |
| -------------- | ------------------ | ------------------------ |
| Ethereum       | ✅ Bridge complete | Aave V3, Uniswap         |
| Aptos (native) | ⚠️ Adapter stubbed | Aries, Echelon, Thala    |
| Solana         | 🗓 Planned          | Marinade staking, Kamino |
| Arbitrum       | 🗓 Planned          | GMX, Radiant             |
| Polygon        | 🗓 Planned          | Aave V3, QuickSwap       |
| Avalanche      | 🗓 Planned          | Benqi, Trader Joe        |

Each new chain needs:

1. A new `*_bridge_adapter.move` on Aptos (mirrors `eth_bridge_adapter.move`)
2. A new strategy executor contract on the target chain (mirrors `EthStrategyExecutor.sol`)
3. A new `eth_listener`-style indexer in the offchain layer
4. LayerZero trusted remote configuration on both ends

## Implementation Status

| Component                     | Status             | Notes                                      |
| ----------------------------- | ------------------ | ------------------------------------------ |
| Aptos vault core              | ✅ Complete        | deposit, withdraw, deploy, recall, harvest |
| OFT bridge (Aptos ↔ Ethereum) | ✅ Complete        | LayerZero V1, 57-byte payload              |
| Ethereum VaultOFT             | ✅ Complete        | wAPT ERC-20 + LZ messaging                 |
| Ethereum strategy executor    | ⚠️ Bridge complete | Aave/DEX integration stubbed               |
| Aptos lending adapter         | ❌ Stubbed         | Aries/Echelon integration needed           |
| Offchain: Yield Engine        | ✅ Complete        | strategy scoring, deploy/harvest logic     |
| Offchain: Risk Engine         | ✅ Complete        | exposure limits, stale bridge detection    |
| Offchain: Analytics Index     | ✅ Complete        | APY tracking, TVL history                  |
| Offchain: Orchestrator        | ✅ Complete        | intent builder + Aptos executor            |
| Pause / circuit breaker       | ❌ Missing         | flag exists, no functions                  |
| Fee collection                | ❌ Missing         | bps stored, never distributed              |
| Multi-sig / timelock          | ❌ Missing         | single operator key                        |
