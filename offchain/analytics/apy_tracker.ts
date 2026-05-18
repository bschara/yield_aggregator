import { HarvestEventData, DeployEventData } from "../indexer/on_chain_listener.js";

const OCTAS_PER_APT = 1e8;
const SECONDS_PER_YEAR = 365 * 24 * 3600;
const TVL_RING_SIZE = 30;

export type ApyMap = Map<number, number>;

interface StrategyYieldRecord {
  deployedOctas: bigint;
  deployTs: number;       // unix seconds of first deploy
  cumulativeYield: number; // APT
  lastHarvestTs: number;
  harvestCount: number;
}

interface TvlSnapshot {
  tvl: number; // APT
  ts: number;  // unix seconds
}

const yieldRecords = new Map<number, StrategyYieldRecord>();
const tvlHistory: TvlSnapshot[] = [];

// Call once per loop tick with new events from the chain.
// deployedAmounts: current on-chain allocation per strategy (in octas).
export function update(
  harvestEvents: HarvestEventData[],
  deployEvents: DeployEventData[],
  deployedAmounts: Map<number, bigint>,
  currentTvl: number,
  nowTs: number
): void {
  // Record TVL snapshot (ring buffer)
  tvlHistory.push({ tvl: currentTvl, ts: nowTs });
  if (tvlHistory.length > TVL_RING_SIZE) tvlHistory.shift();

  // Update deploy timestamps — first deploy for a strategy sets deployTs
  for (const ev of deployEvents) {
    const id = parseInt(ev.strategy_id);
    const evTs = parseInt(ev.timestamp) / 1_000_000; // microseconds → seconds
    if (!yieldRecords.has(id)) {
      yieldRecords.set(id, {
        deployedOctas: deployedAmounts.get(id) ?? 0n,
        deployTs: evTs,
        cumulativeYield: 0,
        lastHarvestTs: 0,
        harvestCount: 0,
      });
    }
    const rec = yieldRecords.get(id)!;
    rec.deployedOctas = deployedAmounts.get(id) ?? rec.deployedOctas;
  }

  // Credit harvests — each harvest event increments yield counter.
  // Since the on-chain HarvestEvent doesn't carry the yield amount we
  // estimate yield from the vault's credit_bridge_harvest path, which
  // updates total_assets. For now we record harvest timestamps for APY
  // window calculation; actual yield amounts are credited when the
  // Analytics layer observes a total_assets increase after harvest.
  for (const ev of harvestEvents) {
    const id = parseInt(ev.strategy_id);
    const evTs = parseInt(ev.timestamp) / 1_000_000;
    if (!yieldRecords.has(id)) {
      yieldRecords.set(id, {
        deployedOctas: deployedAmounts.get(id) ?? 0n,
        deployTs: evTs,
        cumulativeYield: 0,
        lastHarvestTs: evTs,
        harvestCount: 1,
      });
    } else {
      const rec = yieldRecords.get(id)!;
      rec.lastHarvestTs = evTs;
      rec.harvestCount += 1;
    }
  }
}

// Credit an observed yield amount (APT) to a strategy.
// Called by the main loop when it detects a total_assets increase after harvest.
export function creditYield(strategyId: number, yieldApt: number, ts: number): void {
  const rec = yieldRecords.get(strategyId);
  if (!rec) return;
  rec.cumulativeYield += yieldApt;
  rec.lastHarvestTs = ts;
}

// Annualised yield rate for a strategy.
// Returns 0 if not enough data.
export function computeApy(strategyId: number, nowTs: number): number {
  const rec = yieldRecords.get(strategyId);
  if (!rec || rec.deployedOctas === 0n) return 0;

  const elapsed = nowTs - rec.deployTs;
  if (elapsed < 60) return 0; // not enough history

  const deployedApt = Number(rec.deployedOctas) / OCTAS_PER_APT;
  if (deployedApt === 0) return 0;

  const annualisationFactor = SECONDS_PER_YEAR / elapsed;
  return (rec.cumulativeYield / deployedApt) * annualisationFactor;
}

export function buildApyMap(nowTs: number): ApyMap {
  const map: ApyMap = new Map();
  for (const id of yieldRecords.keys()) {
    map.set(id, computeApy(id, nowTs));
  }
  return map;
}

export function getLastHarvestTsMap(): Map<number, number> {
  const map = new Map<number, number>();
  for (const [id, rec] of yieldRecords) {
    map.set(id, rec.lastHarvestTs);
  }
  return map;
}

export function getTvlHistory(): TvlSnapshot[] {
  return [...tvlHistory];
}
