import { describe, it, expect } from "vitest";
import {
  Action,
  buildDeployIntent,
  buildRecallIntent,
  buildHarvestIntent,
  buildExitIntent,
  nextNonce,
} from "../orchestrator/intent_builder.js";

describe("intent_builder", () => {
  describe("buildDeployIntent", () => {
    it("sets action to Deposit (0)", () => {
      const intent = buildDeployIntent(1, 500_000_000);
      expect(intent.action).toBe(Action.Deposit);
    });

    it("sets strategy_id, amount, and fee_amount", () => {
      const intent = buildDeployIntent(3, 200_000_000, 1_000_000);
      expect(intent.strategy_id).toBe(3);
      expect(intent.amount).toBe(200_000_000);
      expect(intent.fee_amount).toBe(1_000_000);
    });

    it("defaults fee_amount to 0", () => {
      const intent = buildDeployIntent(1, 100_000_000);
      expect(intent.fee_amount).toBe(0);
    });

    it("sets target_chain to null", () => {
      expect(buildDeployIntent(1, 100).target_chain).toBeNull();
    });
  });

  describe("buildRecallIntent", () => {
    it("sets action to Withdraw (1)", () => {
      const intent = buildRecallIntent(2, 300_000_000);
      expect(intent.action).toBe(Action.Withdraw);
    });

    it("carries amount and fee through", () => {
      const intent = buildRecallIntent(2, 300_000_000, 5_000_000);
      expect(intent.amount).toBe(300_000_000);
      expect(intent.fee_amount).toBe(5_000_000);
    });
  });

  describe("buildHarvestIntent", () => {
    it("sets action to Harvest (2)", () => {
      const intent = buildHarvestIntent(0);
      expect(intent.action).toBe(Action.Harvest);
    });

    it("always sets amount to 0", () => {
      // harvest doesn't take an amount — the contract determines yield
      const intent = buildHarvestIntent(0, 1_000_000);
      expect(intent.amount).toBe(0);
    });
  });

  describe("buildExitIntent", () => {
    it("sets action to Exit (3)", () => {
      const intent = buildExitIntent(5, 1_000_000_000);
      expect(intent.action).toBe(Action.Exit);
    });
  });

  describe("nextNonce", () => {
    it("is monotonically increasing", () => {
      const n1 = nextNonce();
      const n2 = nextNonce();
      const n3 = nextNonce();
      expect(n2).toBeGreaterThan(n1);
      expect(n3).toBeGreaterThan(n2);
    });

    it("returns unique values for consecutive intent builds", () => {
      const i1 = buildDeployIntent(1, 100);
      const i2 = buildRecallIntent(1, 100);
      const i3 = buildHarvestIntent(1);
      expect(new Set([i1.nonce, i2.nonce, i3.nonce]).size).toBe(3);
    });
  });
});
