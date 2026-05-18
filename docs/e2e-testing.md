# E2E Testing

The e2e test suite simulates a full cross-chain round-trip: Aptos → Ethereum → Aptos, using a local Aptos testnet and a local Hardhat node.

---

## What is Tested

| Scenario | File | Status |
|----------|------|--------|
| DEPLOY round-trip | `bridge_e2e.test.ts` | ✅ |
| RECALL round-trip | `bridge_e2e.test.ts` | ✅ |
| HARVEST round-trip | — | ❌ Missing |
| Multi-operation sequence | — | ❌ Missing |
| Bridge failure / timeout | — | ❌ Missing |

---

## Test Infrastructure

```
e2e-tests/
├── bridge_e2e.test.ts        two round-trip scenarios
└── helpers/
    ├── relay.ts              relay functions (Aptos→Eth, Eth→Aptos) + payload codec
    └── aptos.ts              Aptos SDK localnet helpers (submit txns, read vault state)
```

The Ethereum side uses the same `LZEndpointMock` from `ethereum/contracts/test/` — the same mock used in Hardhat unit tests, wired for auto-delivery between two endpoints.

The Aptos side connects to a real local testnet via the Aptos TS SDK.

---

## Running the Tests

### Option 1: Makefile (recommended)

```bash
make test-e2e
```

This starts both local nodes, waits 5 seconds, runs the tests, and kills the nodes.

### Option 2: Manual

**Terminal 1 — Aptos local testnet:**

```bash
aptos node run-local-testnet --with-faucet
# Starts on http://localhost:8080
# Faucet on http://localhost:8081
```

**Terminal 2 — Ethereum local node:**

```bash
cd ethereum && npx hardhat node
# Starts on http://localhost:8545
```

**Terminal 3 — Run tests:**

```bash
cd e2e-tests
npm test
```

---

## Test Flow: DEPLOY Round-Trip

```
1. Deploy Aptos contracts to localnet
2. Deploy VaultOFT + EthStrategyExecutor to Hardhat node
3. Wire trusted remotes on both sides
4. Operator submits deploy_and_bridge.move script on Aptos
   └─ vault: idle_assets -= amount, deployed_assets += amount
   └─ APT locked in oft_bridge state
5. helpers/relay.ts relays the LZ message to Ethereum
   └─ VaultOFT.lzReceive() called
   └─ wAPT minted to EthStrategyExecutor
   └─ executeIncoming() called (deployedAmounts tracked)
6. Assert: Ethereum deployedAmounts[strategyId] == amount
7. Assert: Aptos vault deployed_assets == amount
```

## Test Flow: RECALL Round-Trip

```
1. (continuing from DEPLOY state)
2. helpers/relay.ts sends ACTION_RECALL to Ethereum
   └─ EthStrategyExecutor._recall() burns wAPT
   └─ _sendBackToAptos() encodes ACTION_COMPLETE, calls lzSend()
3. helpers/relay.ts relays ACTION_COMPLETE to Aptos
   └─ oft_bridge.lz_receive() unlocks APT
   └─ message_receiver.handle_incoming(ACTION_COMPLETE)
   └─ vault.credit_bridge_return()
4. Assert: Aptos vault deployed_assets == 0
5. Assert: Aptos vault idle_assets restored
6. Assert: Ethereum deployedAmounts[strategyId] == 0
```

---

## Adding New Test Scenarios

### HARVEST round-trip

```typescript
it("harvest round-trip", async () => {
  // 1. Set up: deploy capital first
  await deployCapital(amount);

  // 2. Simulate yield accrual on Ethereum
  // (currently requires manually crediting deployedAmounts in executor
  //  or waiting for Aave integration)

  // 3. Send ACTION_HARVEST to Ethereum
  await relay.sendHarvestSignal(strategyId, nonce);

  // 4. Relay COMPLETE + yield back to Aptos
  await relay.relayEthToAptos();

  // 5. Assert vault.total_assets increased
  const vault = await aptos.readVaultState(VAULT_ADDR);
  expect(vault.total_assets).toBeGreaterThan(initialTotalAssets);
});
```

### Bridge timeout scenario

```typescript
it("detects stale bridge message", async () => {
  // 1. Block the LZ endpoint (simulate dropped message)
  lzEndpointMock.blockNextMsg();

  // 2. Send deploy — APT locked but COMPLETE never arrives
  await deployCapital(amount);

  // 3. Advance time past BRIDGE_TIMEOUT_SEC
  await time.increase(700);

  // 4. Check that eth_listener flags it as stale
  const stale = ethListener.getPendingBridgeMessages(600);
  expect(stale.length).toBe(1);

  // 5. Force resume
  await lzEndpointMock.forceResumeReceive(APTOS_CHAIN_ID, path);
});
```

---

## Debugging Failed Tests

**APT not unlocking on Aptos:**
- Check trusted remote is set correctly on `oft_bridge` (`set_trusted_remote` called with correct 32-byte Ethereum address)
- Check nonce hasn't been used before

**wAPT not minting on Ethereum:**
- Check `strategyExecutor` is set on `VaultOFT`
- Check trusted remote path format: `abi.encodePacked(aptosBridgeAddr, vaultOftAddr)`

**Relay fails silently:**
- Check payload length is exactly 57 bytes
- Check action byte matches constants on both sides

**LZ fee errors:**
- Pass enough ETH for `estimateLzFee` when calling `lzSend`; `LZEndpointMock` uses `0.001 ETH + 1000 wei/byte`
