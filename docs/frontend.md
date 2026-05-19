# Frontend

A Vite + React 19 SPA that reads vault state from Aptos RPC and Ethereum RPC, forwards it to the Python policy server, and lets users interact with the vault via Petra wallet.

---

## Component Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                          App (main.tsx)                          │
│    QueryClientProvider · AptosWalletAdapterProvider · Router     │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐   │
│  │  Navbar: nav links · wallet connect button · health dot   │   │
│  └───────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌──────────┐  ┌────────────┐  ┌───────────┐  ┌─────────────┐   │
│  │Dashboard │  │ Strategies │  │ Portfolio │  │   Bridge    │   │
│  └────┬─────┘  └─────┬──────┘  └─────┬─────┘  └──────┬──────┘   │
│       │              │               │                │          │
│  ┌────▼──────────────▼───────────────▼────────────────▼────────┐ │
│  │              DATA HOOKS  (TanStack React Query)              │ │
│  │  useVaultState · useStrategyList · useUserShares             │ │
│  │  useBridgeStatus · usePolicyDecision · usePolicyHealth       │ │
│  └────┬──────────────────────────────────────────────────────┘  │
│       │                                                          │
│  ┌────▼──────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │  lib/aptos.ts │  │ lib/ethereum.ts  │  │  lib/policy.ts   │  │
│  │  Aptos SDK v5 │  │  ethers v6       │  │  Python FastAPI  │  │
│  └───────────────┘  └──────────────────┘  └──────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

---

## Pages

| Page       | Route         | Data hooks                                              | Refetch cadence |
| ---------- | ------------- | ------------------------------------------------------- | --------------- |
| Dashboard  | `/`           | `useVaultState`, `useStrategyList`, `usePolicyDecision` | 10s / 15s / 30s |
| Strategies | `/strategies` | `useStrategyList`                                       | 15s             |
| Portfolio  | `/portfolio`  | `useVaultState`, `useUserShares`                        | 10s / 12s       |
| Bridge     | `/bridge`     | `useBridgeStatus`                                       | 15s             |

### Dashboard (`/`)

Displays four metric cards (TVL, idle capital, deployed capital, active strategy count), a `CapitalBreakdown` pie chart (idle vs deployed), and a `PolicyRecommendation` showing the latest decision from the Python engine. Requires no wallet connection.

### Strategies (`/strategies`)

Grid of `StrategyCard` components showing each registered strategy: ID, adapter type, max exposure, risk score, deployed amount, active status. Read-only.

### Portfolio (`/portfolio`)

Requires a connected Petra wallet. Shows the user's share balance and estimated APT value (`shares × totalAssets / shareSupply`). Deposit and Withdraw buttons open modals that sign transactions via the wallet adapter.

### Bridge (`/bridge`)

Lists cross-chain events from the last 2000 Ethereum blocks. Shows incoming `CrossChainReceive` and outgoing `CrossChainSent` events with action type, amount, strategy ID, nonce, block number, and transaction hash.

---

## Data Hooks

All hooks live in `src/hooks/` and use TanStack React Query.

| Hook                | Exported from        | lib function                 | Refetch | Enabled                  | Retry |
| ------------------- | -------------------- | ---------------------------- | ------- | ------------------------ | ----- |
| `useVaultState`     | `useVaultState.ts`   | `fetchVaultState()`          | 10s     | always                   | 2     |
| `useStrategyList`   | `useVaultState.ts`   | `fetchStrategyList()`        | 15s     | always                   | 2     |
| `useUserShares`     | `useUserShares.ts`   | `fetchUserShares(addr)`      | 12s     | `connected && !!account` | —     |
| `useBridgeStatus`   | `useBridgeStatus.ts` | `fetchPendingBridges()`      | 15s     | always                   | 1     |
| `usePolicyDecision` | `usePolicyScore.ts`  | `fetchPolicyDecision(state)` | 30s     | `!!vaultState`           | —     |
| `usePolicyHealth`   | `usePolicyScore.ts`  | `checkPolicyHealth()`        | 30s     | always                   | —     |

---

## Data Sources

### `lib/aptos.ts` — Aptos SDK v5

Reads on-chain resources from the Aptos fullnode and builds transaction payloads.

| Function                               | Description                                                                               |
| -------------------------------------- | ----------------------------------------------------------------------------------------- |
| `fetchVaultState()`                    | Reads `Vault` resource: `total_assets`, `idle_assets`, `deployed_capital`, `share_supply` |
| `fetchStrategyList()`                  | Reads `Registry` resource, maps the strategy array to typed objects                       |
| `fetchUserShares(walletAddr)`          | Reads `ShareBalance` resource for the connected address; returns `0n` if not found        |
| `buildDepositPayload(amountOctas)`     | Returns a typed entry function payload for `vault::deposit_entry`                         |
| `buildWithdrawPayload(depositObjAddr)` | Returns a typed entry function payload for `vault::withdraw`                              |
| `octasToApt(octas)`                    | Converts octas to APT (divides by `1e8`)                                                  |

### `lib/ethereum.ts` — ethers v6

| Function                | Description                                                                                                           |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `fetchPendingBridges()` | Queries the last 2000 blocks for `CrossChainReceive` and `CrossChainSent` events on VaultOFT; returns `BridgeEvent[]` |

### `lib/policy.ts` — Python FastAPI

| Function                          | Description                                                                                                     |
| --------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `fetchPolicyDecision(vaultState)` | `POST /decide` with the current vault state; returns `PolicyDecision { type, strategyId, amountOctas, reason }` |
| `checkPolicyHealth()`             | `GET /health`; returns `true` if the engine responds `{ status: "ok" }`                                         |

---

## Wallet Integration

- **Provider**: `AptosWalletAdapterProvider` wraps the app with `optInWallets={["Petra"]}` and `autoConnect={false}`. No plugin packages needed — wallet-adapter v8 discovers Petra via the AIP-62 browser injection standard.
- **Hook**: `useWallet()` exposes `connected`, `account`, `connect(walletName)`, `disconnect()`, `signAndSubmitTransaction(payload)`.
- **Address type**: `account.address` is `AccountAddress`, not a string. Call `.toString()` before passing to query keys, RPC calls, or display.
- **Transactions**: `DepositModal` and `WithdrawModal` call `signAndSubmitTransaction({ data: payload })` and poll for confirmation.

---

## UI Components

### Layout & common (`src/components/layout/`, `src/components/common/`)

| Component     | Purpose                                                                           |
| ------------- | --------------------------------------------------------------------------------- |
| `Navbar`      | Top navigation bar; wallet connect button; green/red health dot for policy engine |
| `PageLayout`  | Wraps page content with a page title and consistent padding                       |
| `Card`        | Generic bordered container                                                        |
| `Badge`       | Coloured label (variants: green, yellow, purple, gray)                            |
| `Spinner`     | Loading indicator                                                                 |
| `ErrorBanner` | Red inline error message                                                          |
| `EmptyState`  | No-data placeholder with icon and caption                                         |

### Domain components

| Component              | Location      | Purpose                                                                  |
| ---------------------- | ------------- | ------------------------------------------------------------------------ |
| `MetricCard`           | `dashboard/`  | Label + value + sub-text tile used on the Dashboard                      |
| `CapitalBreakdown`     | `dashboard/`  | Recharts pie chart of idle vs deployed capital                           |
| `PolicyRecommendation` | `dashboard/`  | Shows policy engine decision type (badge) + reason text                  |
| `StrategyCard`         | `strategies/` | Strategy details: ID, risk score, max exposure, deployed amount          |
| `RiskBadge`            | `strategies/` | Colour-coded risk level label                                            |
| `BridgeActivityFeed`   | `bridge/`     | Table of recent bridge events with type, amount, strategy, block         |
| `DepositModal`         | `vault/`      | Amount input, APT → octas conversion, sign + submit, success/error state |
| `WithdrawModal`        | `vault/`      | Deposit object address input, sign + submit                              |

---

## Styling

- **Tailwind CSS v4** — configured via the `@tailwindcss/vite` Vite plugin. There is no `tailwind.config.js`; content scanning is automatic.
- **Custom brand palette** defined in `src/index.css` using the CSS-first `@theme` block:
  ```css
  @theme {
    --color-brand-50: #f5f3ff;
    --color-brand-500: #7c3aed;
    --color-brand-600: #6d28d9;
    --color-brand-700: #5b21b6;
  }
  ```
- **Dark-first base**: `bg-gray-950 text-gray-100 antialiased` on `body`.

---

## Configuration

Copy `frontend/.env.example` to `frontend/.env` and fill in the required values:

| Variable                 | Default                                    | Required | Purpose                        |
| ------------------------ | ------------------------------------------ | -------- | ------------------------------ |
| `VITE_APTOS_RPC`         | `https://fullnode.devnet.aptoslabs.com/v1` | No       | Aptos fullnode URL             |
| `VITE_APTOS_MODULE_ADDR` | —                                          | Yes      | Deployed module address        |
| `VITE_VAULT_ADDR`        | —                                          | Yes      | Vault resource account address |
| `VITE_REGISTRY_ADDR`     | —                                          | Yes      | Strategy registry address      |
| `VITE_ETH_RPC`           | `https://sepolia.infura.io/v3/YOUR_KEY`    | No       | Ethereum RPC endpoint          |
| `VITE_VAULT_OFT_ADDR`    | —                                          | Yes      | VaultOFT contract address      |
| `VITE_POLICY_SERVER_URL` | `http://localhost:8001`                    | No       | Python policy server URL       |

All variables are prefixed with `VITE_` so Vite exposes them to the browser bundle via `import.meta.env`.

---

## Running

```bash
cd frontend
cp .env.example .env   # fill in required vars
npm install
npm run dev            # dev server → http://localhost:5173
npm run build          # TypeScript check + Vite production build
npm run preview        # serve the production build locally
npm run lint           # ESLint
```

The policy server must be running for the `PolicyRecommendation` widget and the engine health dot to show live data (the rest of the UI degrades gracefully if it is offline).
