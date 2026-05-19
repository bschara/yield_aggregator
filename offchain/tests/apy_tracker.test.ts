import { describe, it, expect, vi } from "vitest";

// on_chain_listener exports only the Aptos client + types — mock the module so
// the Aptos SDK isn't initialised during unit tests.
vi.mock("../indexer/on_chain_listener.js", () => ({ aptos: {} }));

import {
  update,
  creditYield,
  computeApy,
  buildApyMap,
  getLastHarvestTsMap,
  getTvlHistory,
} from "../analytics/apy_tracker.js";
import type { HarvestEventData, DeployEventData } from "../indexer/on_chain_listener.js";

// Helper: build a fake DeployEvent with the given strategy ID and timestamp (seconds).
function fakeDeployEvent(strategyId: number, tsSeconds: number): DeployEventData {
  return {
    strategy_id: String(strategyId),
    amount: "100000000",
    timestamp: String(tsSeconds * 1_000_000), // apy_tracker converts µs → s
    sequence_number: "0",
  } as DeployEventData;
}

function fakeHarvestEvent(strategyId: number, tsSeconds: number): HarvestEventData {
  return {
    strategy_id: String(strategyId),
    timestamp: String(tsSeconds * 1_000_000),
    sequence_number: "0",
  } as HarvestEventData;
}

const SECONDS_PER_YEAR = 365 * 24 * 3600;

describe("apy_tracker", () => {
  // ── computeApy ───────────────────────────────────────────────────────────

  describe("computeApy", () => {
    it("returns 0 for an unknown strategy", () => {
      expect(computeApy(9999, 2_000_000)).toBe(0);
    });

    it("returns 0 when elapsed time is less than 60 seconds", () => {
      const deployTs = 1_000_000;
      update([fakeHarvestEvent(101, deployTs)], [fakeDeployEvent(101, deployTs)],
        new Map([[101, 1_000_000_000n]]), 10, deployTs);
      creditYield(101, 1, deployTs);
      // only 30 seconds later → too early to compute reliable APY
      expect(computeApy(101, deployTs + 30)).toBe(0);
    });

    it("computes correct annualised yield after sufficient history", () => {
      // Deploy 100 APT (10_000_000_000 octas) at t=0, earn 5 APT over one year.
      const deployTs = 2_000_000;
      const deployed = 10_000_000_000n; // 100 APT
      update([], [fakeDeployEvent(102, deployTs)],
        new Map([[102, deployed]]), 100, deployTs);
      creditYield(102, 5, deployTs + SECONDS_PER_YEAR);

      const apy = computeApy(102, deployTs + SECONDS_PER_YEAR);
      // Expected: (5 / 100) * (SECONDS_PER_YEAR / SECONDS_PER_YEAR) = 0.05
      expect(apy).toBeCloseTo(0.05, 5);
    });

    it("scales linearly with yield amount", () => {
      const deployTs = 3_000_000;
      const halfYear = SECONDS_PER_YEAR / 2;
      update([], [fakeDeployEvent(103, deployTs)],
        new Map([[103, 1_000_000_000n]]), 10, deployTs); // 10 APT
      creditYield(103, 1, deployTs + halfYear); // 1 APT over half year = 20% APY

      const apy = computeApy(103, deployTs + halfYear);
      expect(apy).toBeCloseTo(0.2, 4);
    });
  });

  // ── creditYield ──────────────────────────────────────────────────────────

  describe("creditYield", () => {
    it("accumulates multiple yield credits", () => {
      const deployTs = 4_000_000;
      update([], [fakeDeployEvent(104, deployTs)],
        new Map([[104, 1_000_000_000n]]), 10, deployTs);
      creditYield(104, 2, deployTs + 1000);
      creditYield(104, 3, deployTs + SECONDS_PER_YEAR);

      // Total: 5 APT over one year on 10 APT deployed = 50% APY
      const apy = computeApy(104, deployTs + SECONDS_PER_YEAR);
      expect(apy).toBeCloseTo(0.5, 3);
    });

    it("is a no-op for unknown strategy", () => {
      expect(() => creditYield(99999, 10, 1_000_000)).not.toThrow();
    });
  });

  // ── buildApyMap ──────────────────────────────────────────────────────────

  describe("buildApyMap", () => {
    it("returns a map containing all known strategy IDs", () => {
      const deployTs = 5_000_000;
      update([], [fakeDeployEvent(201, deployTs), fakeDeployEvent(202, deployTs)],
        new Map([[201, 1_000_000_000n], [202, 1_000_000_000n]]), 20, deployTs);

      const map = buildApyMap(deployTs + SECONDS_PER_YEAR);
      expect(map.has(201)).toBe(true);
      expect(map.has(202)).toBe(true);
    });

    it("returns numeric APY values", () => {
      const map = buildApyMap(Date.now() / 1000);
      for (const apy of map.values()) {
        expect(typeof apy).toBe("number");
        expect(apy).toBeGreaterThanOrEqual(0);
      }
    });
  });

  // ── getLastHarvestTsMap ──────────────────────────────────────────────────

  describe("getLastHarvestTsMap", () => {
    it("reflects the last harvest timestamp from update()", () => {
      const harvestTs = 6_000_000;
      update([fakeHarvestEvent(301, harvestTs)], [],
        new Map([[301, 1_000_000_000n]]), 10, harvestTs);

      const map = getLastHarvestTsMap();
      expect(map.has(301)).toBe(true);
      expect(map.get(301)).toBe(harvestTs); // ts is in seconds after µs→s conversion
    });
  });

  // ── getTvlHistory ────────────────────────────────────────────────────────

  describe("getTvlHistory", () => {
    it("caps at 30 entries regardless of starting state", () => {
      // Push 40 snapshots — ring buffer must clamp to 30
      for (let i = 0; i < 40; i++) {
        update([], [], new Map(), i * 1000, 10_000_000 + i);
      }
      expect(getTvlHistory().length).toBeLessThanOrEqual(30);
    });

    it("returns a copy (mutations don't affect internal state)", () => {
      const h1 = getTvlHistory();
      h1.push({ tvl: 9999, ts: 0 });
      const h2 = getTvlHistory();
      expect(h2).not.toContainEqual({ tvl: 9999, ts: 0 });
    });
  });
});
