import { ApyMap } from "../analytics/apy_tracker.js";
import { ChainSnapshot, readAllocationFromTable } from "./on_chain_listener.js";

const OCTAS_PER_APT = 1e8;

export interface StrategyPosition {
  strategyId: string;
  capitalAllocated: number; // APT
  maxExposure: number;      // APT
  apy: number;              // annualized fraction (0.05 = 5%)
  riskScore: number;        // 0–1
  lastHarvestTs: number;    // unix seconds, 0 if never harvested
}

export interface VaultState {
  tvl: number;              // APT
  idleAssets: number;       // APT
  deployedAssets: number;   // APT
  utilization: number;      // 0–1
  strategies: StrategyPosition[];
  snapshotTs: number;
}

// lastHarvestTsMap is maintained by apy_tracker and passed in here
export async function buildVaultState(
  snapshot: ChainSnapshot,
  apyMap: ApyMap,
  lastHarvestTsMap: Map<number, number>
): Promise<VaultState> {
  const { vault, strategies } = snapshot;

  const totalAssets = BigInt(vault.total_assets);
  const idleAssets = BigInt(vault.idle_assets);
  const deployedAssets = BigInt(vault.deployed_assets);

  const tvl = Number(totalAssets) / OCTAS_PER_APT;
  const idle = Number(idleAssets) / OCTAS_PER_APT;
  const deployed = Number(deployedAssets) / OCTAS_PER_APT;
  const utilization = tvl > 0 ? deployed / tvl : 0;

  const positions: StrategyPosition[] = await Promise.all(
    strategies.map(async (s) => {
      const allocated = await readAllocationFromTable(
        vault.allocations.handle,
        s.id
      );
      const capitalAllocated = Number(allocated) / OCTAS_PER_APT;
      const maxExposure = Number(s.max_exposure) / OCTAS_PER_APT;
      const apy = apyMap.get(s.id) ?? 0;
      const lastHarvestTs = lastHarvestTsMap.get(s.id) ?? 0;

      // risk = utilization pressure + over-exposure penalty
      const exposureRatio = maxExposure > 0 ? capitalAllocated / maxExposure : 0;
      const riskScore = Math.min(1, exposureRatio * 0.6 + utilization * 0.4);

      return {
        strategyId: s.id.toString(),
        capitalAllocated,
        maxExposure,
        apy,
        riskScore,
        lastHarvestTs,
      };
    })
  );

  return {
    tvl,
    idleAssets: idle,
    deployedAssets: deployed,
    utilization,
    strategies: positions,
    snapshotTs: snapshot.snapshotTs,
  };
}
