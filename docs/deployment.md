# Deployment Guide

---

## Prerequisites

| Tool      | Version | Install                            |
| --------- | ------- | ---------------------------------- |
| Aptos CLI | ≥ 4.x   | https://aptos.dev/tools/aptos-cli/ |
| Node.js   | ≥ 20    | https://nodejs.org                 |
| Python    | ≥ 3.11  | https://python.org                 |
| Git       | any     |                                    |

---

## 1. Clone and install

```bash
git clone <repo>
cd cross_platform_yield_aggregator

cd ethereum && npm install && cd ..

cd e2e-tests && npm install && cd ..

make install-offchain
```

---

## 2. Configure accounts

You need:

- An **Aptos deployer account** with enough APT for gas + vault seeding
- An **Aptos operator account** (can be the same for testnet)
- An **Ethereum deployer account** with ETH for gas

```bash
aptos init --network testnet

aptos account fund-with-faucet --account <your_address>
```

---

## 3. Deploy Aptos contracts

```bash
cd aptos

aptos move compile --named-addresses YieldAggregator=<your_addr>
aptos move publish --named-addresses YieldAggregator=<your_addr>

```

### Initialize on-chain components

Run these once after publishing:

```bash
aptos move run \
  --function-id <module_addr>::yield_vault::init \
  --assume-yes

aptos move run \
  --function-id <module_addr>::strategy_registry::init \
  --assume-yes

aptos move run \
  --function-id <module_addr>::strategy_executor::init \
  --assume-yes

aptos move run \
  --function-id <module_addr>::oft_bridge::init \
  --args u8:8 \
  --assume-yes
```

### Derive addresses

```bash
aptos move view \
  --function-id <module_addr>::yield_vault::vault_address \
  --args address:<deployer_addr>

```

---

## 4. Deploy Ethereum contracts

```bash
cd ethereum

cp .env.example .env

npx hardhat run scripts/deploy.ts --network sepolia

```

---

## 5. Wire up cross-chain trust

Both sides must whitelist each other before any messages can be relayed.

### Aptos side — trust the Ethereum OFT

```bash
aptos move run \
  --function-id <module_addr>::oft_bridge::set_trusted_remote \
  --args \
    address:<bridge_addr> \
    u64:101 \
    hex:<vault_oft_addr_padded_to_32_bytes> \
  --assume-yes
```

### Ethereum side — trust the Aptos bridge

```javascript
const vaultOft = await ethers.getContractAt("VaultOFT", VAULT_OFT_ADDR);

// path = abi.encodePacked(aptosOftBridgeAddr, vaultOftAddr)
// (standard LayerZero V1 trusted remote format)
const path = ethers.concat([APTOS_BRIDGE_ADDR_BYTES32, VAULT_OFT_ADDR]);
await vaultOft.setTrustedRemote(108, path); // 108 = Aptos LZ chain ID

await vaultOft.setStrategyExecutor(EXECUTOR_ADDR);
```

### Ethereum executor — set Aptos bridge address

```javascript
const executor = await ethers.getContractAt(
  "EthStrategyExecutor",
  EXECUTOR_ADDR
);
await executor.setAptosBridgeAddress(APTOS_BRIDGE_ADDR_BYTES32);
```

---

## 6. Register a strategy

```bash
# Register Ethereum bridge strategy
# risk levels: 0=Low, 1=Medium, 2=High
aptos move run \
  --function-id <module_addr>::strategy_registry::add_strategy \
  --args \
    address:<registry_addr> \
    address:<eth_bridge_adapter_addr> \
    u64:10000000000 \
    u8:1 \
  --assume-yes
# max_exposure = 10000000000 octas = 100 APT
```

---

## 7. Compile Move scripts (required for offchain executor)

```bash
cd aptos
aptos move compile --named-addresses YieldAggregator=<your_addr>

# Compiled bytecodes land in:
# aptos/build/yield_aggregator/bytecode_scripts/
#   deploy_and_bridge.mv
#   harvest_and_send.mv
#   recall_and_send.mv
```

The offchain executor loads these `.mv` files at runtime.

---

## 8. Configure and start offchain engine

```bash
cd offchain
cp .env.example .env
```

Fill in all values in `.env`:

```
APTOS_RPC=https://fullnode.testnet.aptoslabs.com/v1
APTOS_MODULE_ADDR=0x<your_deployed_module_addr>
VAULT_ADDR=0x<vault_resource_account_addr>
REGISTRY_ADDR=0x<registry_resource_account_addr>
ENGINE_ADDR=0x<deployer_addr>   # ExecutionState lives on the deployer
OPERATOR_PRIVATE_KEY=<ed25519_private_key_hex>
ETH_RPC=https://sepolia.infura.io/v3/<your_key>
VAULT_OFT_ADDR=0x<vault_oft_addr>
```

```bash
make start-policy

make start-offchain
```

---

## Testnet vs Mainnet

| Setting              | Testnet (Sepolia / Aptos testnet) | Mainnet             |
| -------------------- | --------------------------------- | ------------------- |
| Aptos network        | `--network testnet`               | `--network mainnet` |
| LZ Ethereum chain ID | `10161` (Sepolia)                 | `101`               |
| LZ Aptos chain ID    | `10108`                           | `108`               |
| APT faucet           | Available                         | N/A                 |

Update `ETH_CHAIN_ID` in `eth_bridge_adapter.move` before deploying to mainnet.

---

## Security checklist before mainnet

- [ ] Move contracts audited by external security firm
- [ ] Multi-sig set as vault owner (replace single deployer key)
- [ ] Operator key stored in HSM or secure enclave
- [ ] Trusted remote addresses verified on both chains
- [ ] `max_exposure` limits set conservatively (start small)
- [ ] Pause/circuit breaker mechanism added to vault
- [ ] Aave + DEX integrations in `EthStrategyExecutor` audited
- [ ] Bridge timeout and recovery flow tested on testnet
- [ ] Monitoring + alerting set up for bridge message latency
