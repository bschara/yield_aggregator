# Ethereum Contracts

All contracts live in `ethereum/contracts/`. Built with Solidity 0.8.22 and Hardhat v3.

---

## VaultOFT

`contracts/VaultOFT.sol`

An ERC-20 token representing wrapped APT (wAPT) on Ethereum, combined with a LayerZero V1 messaging endpoint. Acts as the bridge between LayerZero messages and the strategy executor.

### Token Details

| Property | Value                   |
| -------- | ----------------------- |
| Name     | Wrapped APT             |
| Symbol   | wAPT                    |
| Decimals | 8 (matches Aptos octas) |
| Standard | ERC-20 + Ownable        |

### Constants

```solidity
uint16 constant APTOS_CHAIN_ID = 108;
uint8  constant ACTION_DEPLOY   = 0x01;
uint8  constant ACTION_RECALL   = 0x02;
uint8  constant ACTION_HARVEST  = 0x03;
uint8  constant ACTION_COMPLETE = 0x04;
```

### State

```solidity
ILayerZeroEndpoint public immutable lzEndpoint;
address public strategyExecutor;
mapping(uint16 => bytes) public trustedRemotes;  // chainId → trusted sender path
```

### Admin Functions

| Function                                       | Access | Description                                               |
| ---------------------------------------------- | ------ | --------------------------------------------------------- |
| `setStrategyExecutor(address)`                 | Owner  | Registers the executor. Must be called after deployment.  |
| `setTrustedRemote(uint16 chainId, bytes path)` | Owner  | Whitelists an Aptos bridge address for incoming messages. |

### LayerZero Receive (Inbound)

```solidity
function lzReceive(uint16 srcChainId, bytes memory srcAddress, uint64 nonce, bytes memory payload)
```

Called by the LayerZero endpoint. Validates the message comes from a trusted remote, then dispatches:

| Action           | Behaviour                                                                        |
| ---------------- | -------------------------------------------------------------------------------- |
| `ACTION_DEPLOY`  | Mints wAPT to `strategyExecutor`, calls `executeIncoming(amount, payload)`       |
| `ACTION_RECALL`  | Calls `executeIncoming(0, payload)` — signals executor to withdraw from strategy |
| `ACTION_HARVEST` | Calls `executeIncoming(0, payload)` — signals executor to collect yield          |

### LayerZero Send (Outbound)

```solidity
function lzSend(
    uint16 dstChainId,
    bytes calldata destination,
    bytes calldata payload,
    address payable refundAddress,
    bytes calldata adapterParams
) external payable
```

Restricted to `strategyExecutor`. Called when sending COMPLETE messages back to Aptos.

### Token Management (executor only)

| Function                                   | Description                                   |
| ------------------------------------------ | --------------------------------------------- |
| `mintBridge(address to, uint256 amount)`   | Mints wAPT when capital arrives from Aptos.   |
| `burnBridge(address from, uint256 amount)` | Burns wAPT before returning capital to Aptos. |

### Payload Codec

57-byte format, must match `oft_bridge.move`:

```solidity
function encodePayload(
    uint8 action,
    uint64 amount,
    uint64 strategyId,
    uint64 nonce,
    bytes32 vaultAddr
) public pure returns (bytes memory)

function decodePayload(bytes memory payload)
    returns (uint8 action, uint64 amount, uint64 strategyId, uint64 nonce, bytes32 vaultAddr)
```

### Events

| Event                 | Fields                                                        |
| --------------------- | ------------------------------------------------------------- |
| `StrategyExecutorSet` | address executor                                              |
| `TrustedRemoteSet`    | uint16 chainId, bytes path                                    |
| `CrossChainReceive`   | uint16 srcChainId, uint8 action, uint256 amount, uint64 nonce |
| `CrossChainSent`      | uint16 dstChainId, uint8 action, uint256 amount, uint64 nonce |

---

## EthStrategyExecutor

`contracts/EthStrategyExecutor.sol`

Receives cross-chain instructions from Aptos, executes DeFi strategy actions, and sends results back. Currently the bridge wiring is complete; Aave/DEX integrations are stubbed.

### State

```solidity
VaultOFT public immutable oft;
mapping(uint64 => bool)    public executedNonces;
mapping(uint64 => uint256) public deployedAmounts;
bytes32 public aptosBridgeAddress;
uint256 constant MIN_GAS_LIMIT = 300_000;
uint16  constant APTOS_CHAIN_ID = 108;
```

### Admin Functions

| Function                         | Access | Description                                             |
| -------------------------------- | ------ | ------------------------------------------------------- |
| `setAptosBridgeAddress(bytes32)` | Owner  | Sets the destination for outbound LZ messages to Aptos. |

### Main Entry Point

```solidity
function executeIncoming(uint256 amount, bytes calldata payload) external
```

Called by `VaultOFT._nonblockingLzReceive`. Decodes payload, checks nonce, routes to action handler.

### Strategy Handlers

| Function                                                                      | Status     | Intended Behaviour                                                  |
| ----------------------------------------------------------------------------- | ---------- | ------------------------------------------------------------------- |
| `_deploy(uint64 strategyId, uint256 amount, uint64 nonce)`                    | ⚠️ Stub    | Swap wAPT → USDC via DEX, deposit into Aave V3                      |
| `_recall(uint64 strategyId, uint256 amount, bytes32 vaultAddr, uint64 nonce)` | ⚠️ Partial | Withdraw from Aave (TODO), swap USDC → wAPT, send COMPLETE to Aptos |
| `_harvest(uint64 strategyId, bytes32 vaultAddr, uint64 nonce)`                | ⚠️ Stub    | Claim Aave rewards, convert to wAPT, send COMPLETE to Aptos         |

Current behaviour of `_recall` without Aave integration: burns wAPT directly (using `deployedAmounts` tracking) and sends COMPLETE back to Aptos, so the round-trip accounting works even while DeFi integrations are absent.

### Send Back to Aptos

```solidity
function _sendBackToAptos(
    uint256 amount,
    bytes32 vaultAddr,
    uint64 strategyId,
    uint64 nonce
) internal
```

Burns wAPT from executor, encodes ACTION_COMPLETE payload, estimates LZ fees, calls `oft.lzSend()`.

### Fee Estimation

```solidity
function estimateSendBackFee(
    uint64 strategyId,
    uint64 amount,
    bytes32 vaultAddr,
    uint64 nonce
) external view returns (uint256 nativeFee, uint256 zroFee)
```

### Events

| Event             | Fields                            |
| ----------------- | --------------------------------- |
| `Deploy`          | strategyId, amount, nonce         |
| `Recall`          | strategyId, amount, nonce         |
| `Harvest`         | strategyId, yieldAmount, nonce    |
| `SentBackToAptos` | strategyId, amount, action, nonce |

---

## Test Helpers

### LZEndpointMock (`contracts/test/LZEndpointMock.sol`)

Simulates LayerZero V1 endpoint behaviour for local testing.

Key features:

- Fee math: `BASE_FEE (0.001 ETH) + FEE_PER_BYTE (1000 wei × payload length)`
- Nonce tracking per chain/path
- `setDestLzEndpoint(addr, endpoint)` — wires two endpoints for auto-delivery
- `blockNextMsg()` + `forceResumeReceive()` — tests message blocking and retry

### FakeAptosReceiver (`contracts/test/FakeAptosReceiver.sol`)

EVM stand-in for `oft_bridge.move`. Captures all messages sent back to Aptos from the executor, stores full history with chainId, srcAddress, nonce, and payload. Used in `BridgeE2E.test.ts` to verify outbound messages.

---

## Hardhat Configuration

```
Networks:   hardhat (local), localhost, sepolia, mainnet
Solidity:   0.8.22, optimizer enabled (200 runs)
```

Run tests:

```bash
cd ethereum
npm test
npx hardhat test test/VaultOFT.test.ts
npx hardhat test test/BridgeE2E.test.ts
```
