import { describe, it, expect, vi, beforeAll } from "vitest";

// mockAptos must be available inside vi.mock() which is hoisted — use vi.hoisted().
const { mockAptos } = vi.hoisted(() => {
  const mockAptos = {
    transaction: { build: { simple: vi.fn() } },
    signAndSubmitTransaction: vi.fn(),
    waitForTransaction: vi.fn(),
  };
  return { mockAptos };
});

vi.mock("../indexer/on_chain_listener.js", () => ({ aptos: mockAptos }));

// Set env vars before the module is imported (they're read at module-load time).
process.env.APTOS_MODULE_ADDR = "0xtest_module";
// Valid 32-byte Ed25519 private key (all-0x11 bytes) — real SDK parses this.
process.env.OPERATOR_PRIVATE_KEY =
  "1111111111111111111111111111111111111111111111111111111111111111";

import { executeIntent } from "../orchestrator/executor.js";
import { Action } from "../orchestrator/intent_builder.js";

const VAULT = "0xvault";
const REGISTRY = "0xregistry";

function baseIntent(action: number, strategyId = 1, amount = 500_000_000) {
  return {
    strategy_id: strategyId,
    action,
    amount,
    fee_amount: 0,
    target_chain: null,
    nonce: 9000 + strategyId,
  };
}

describe("executor — executeIntent", () => {
  beforeAll(() => {
    mockAptos.transaction.build.simple.mockResolvedValue({ raw: "txn" });
    mockAptos.signAndSubmitTransaction.mockResolvedValue({ hash: "0xabc123" });
    mockAptos.waitForTransaction.mockResolvedValue({ success: true });
  });

  it("deploy action calls deploy_and_bridge_entry with 5 args including amount", async () => {
    const result = await executeIntent(baseIntent(Action.Deposit), VAULT, REGISTRY);

    expect(result.success).toBe(true);
    expect(result.action).toBe("deploy");

    const call = mockAptos.transaction.build.simple.mock.calls[0][0] as {
      data: { function: string; functionArguments: unknown[] };
    };
    expect(call.data.function).toContain("deploy_and_bridge_entry");
    // [vault_addr, registry_addr, strategy_id, amount, fee_amount]
    expect(call.data.functionArguments).toHaveLength(5);
    expect(call.data.functionArguments[3]).toBe(500_000_000n); // amount as BigInt
  });

  it("harvest action calls harvest_and_send_entry with 4 args (no amount)", async () => {
    vi.clearAllMocks();
    mockAptos.transaction.build.simple.mockResolvedValue({ raw: "txn" });
    mockAptos.signAndSubmitTransaction.mockResolvedValue({ hash: "0xharvest" });
    mockAptos.waitForTransaction.mockResolvedValue({ success: true });

    const result = await executeIntent(baseIntent(Action.Harvest, 2, 0), VAULT, REGISTRY);

    expect(result.success).toBe(true);
    expect(result.action).toBe("harvest");

    const call = mockAptos.transaction.build.simple.mock.calls[0][0] as {
      data: { function: string; functionArguments: unknown[] };
    };
    expect(call.data.function).toContain("harvest_and_send_entry");
    // [vault_addr, registry_addr, strategy_id, fee_amount] — amount is omitted
    expect(call.data.functionArguments).toHaveLength(4);
  });

  it("recall (Withdraw) action calls recall_and_send_entry", async () => {
    vi.clearAllMocks();
    mockAptos.transaction.build.simple.mockResolvedValue({ raw: "txn" });
    mockAptos.signAndSubmitTransaction.mockResolvedValue({ hash: "0xrecall" });
    mockAptos.waitForTransaction.mockResolvedValue({ success: true });

    const result = await executeIntent(baseIntent(Action.Withdraw, 3), VAULT, REGISTRY);

    expect(result.action).toBe("recall");
    const call = mockAptos.transaction.build.simple.mock.calls[0][0] as {
      data: { function: string };
    };
    expect(call.data.function).toContain("recall_and_send_entry");
  });

  it("exit action also routes to recall_and_send_entry", async () => {
    vi.clearAllMocks();
    mockAptos.transaction.build.simple.mockResolvedValue({ raw: "txn" });
    mockAptos.signAndSubmitTransaction.mockResolvedValue({ hash: "0xexit" });
    mockAptos.waitForTransaction.mockResolvedValue({ success: true });

    const result = await executeIntent(baseIntent(Action.Exit, 4), VAULT, REGISTRY);

    expect(result.action).toBe("exit");
    const call = mockAptos.transaction.build.simple.mock.calls[0][0] as {
      data: { function: string };
    };
    expect(call.data.function).toContain("recall_and_send_entry");
  });

  it("returns success=false and captures the error message on Aptos client throw", async () => {
    vi.clearAllMocks();
    mockAptos.transaction.build.simple.mockRejectedValue(new Error("rpc timeout"));

    const result = await executeIntent(baseIntent(Action.Deposit, 5), VAULT, REGISTRY);

    expect(result.success).toBe(false);
    expect(result.error).toContain("rpc timeout");
    expect(result.txHash).toBe("");
  });

  it("returns success=false when waitForTransaction reports vm failure", async () => {
    vi.clearAllMocks();
    mockAptos.transaction.build.simple.mockResolvedValue({ raw: "txn" });
    mockAptos.signAndSubmitTransaction.mockResolvedValue({ hash: "0xfail" });
    mockAptos.waitForTransaction.mockResolvedValue({
      success: false,
      vm_status: "execution failed",
    });

    const result = await executeIntent(baseIntent(Action.Deposit, 6), VAULT, REGISTRY);

    expect(result.success).toBe(false);
  });
});
