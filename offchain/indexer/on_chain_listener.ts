import { Aptos, AptosConfig } from "@aptos-labs/ts-sdk";

const MODULE = process.env.APTOS_MODULE_ADDR!;

export const aptos = new Aptos(new AptosConfig({ fullnode: process.env.APTOS_RPC }));

// Raw shapes returned by the Aptos node (all numeric fields arrive as strings)
export interface RawVault {
  total_assets: string;
  total_shares: string;
  idle_assets: string;
  deployed_assets: string;
  management_fee_bps: string;
  performance_fee_bps: string;
  owner: string;
  operator: string;
  paused: boolean;
  allocations: { handle: string };
}

export interface RawStrategy {
  id: number;
  adapter: string;
  max_exposure: string;
  risk: { value: number };
  active: boolean;
}

export interface RawRegistry {
  next_id: string;
  strategies: { handle: string };
}

export interface HarvestEventData {
  strategy_id: string;
  timestamp: string;
}

export interface DeployEventData {
  strategy_id: string;
  amount: string;
  timestamp: string;
}

export interface ChainSnapshot {
  vault: RawVault;
  strategies: RawStrategy[];
  harvestEvents: HarvestEventData[];
  deployEvents: DeployEventData[];
  snapshotTs: number;
}

export async function readVaultResource(vaultAddr: string): Promise<RawVault> {
  const resource = await aptos.getAccountResource({
    accountAddress: vaultAddr,
    resourceType: `${MODULE}::yield_vault::Vault`,
  });
  return resource as unknown as RawVault;
}

export async function readRegistryResource(registryAddr: string): Promise<RawRegistry> {
  const resource = await aptos.getAccountResource({
    accountAddress: registryAddr,
    resourceType: `${MODULE}::strategy_registry::Registry`,
  });
  return resource as unknown as RawRegistry;
}

export async function readStrategyFromTable(
  tableHandle: string,
  strategyId: number
): Promise<RawStrategy | null> {
  try {
    const item = await aptos.getTableItem({
      handle: tableHandle,
      data: {
        key_type: "u64",
        value_type: `${MODULE}::strategy_registry::Strategy`,
        key: strategyId.toString(),
      },
    });
    return { ...(item as object), id: strategyId } as RawStrategy;
  } catch {
    return null;
  }
}

export async function readAllocationFromTable(
  tableHandle: string,
  strategyId: number
): Promise<bigint> {
  try {
    const item = await aptos.getTableItem({
      handle: tableHandle,
      data: { key_type: "u64", value_type: "u128", key: strategyId.toString() },
    });
    return BigInt(item as string);
  } catch {
    return 0n;
  }
}

let harvestCursor = 0;
let deployCursor = 0;

const EVENTS_QUERY = `
  query GetEvents($event_type: String!, $limit: Int!, $offset: Int!) {
    events(
      where: { indexed_type: { _eq: $event_type } },
      limit: $limit,
      offset: $offset,
      order_by: { transaction_version: asc }
    ) { data }
  }
`;

export async function pollHarvestEvents(limit = 25): Promise<HarvestEventData[]> {
  const result = await aptos.queryIndexer<{ events: Array<{ data: unknown }> }>({
    query: {
      query: EVENTS_QUERY,
      variables: { event_type: `${MODULE}::yield_vault::HarvestEvent`, limit, offset: harvestCursor },
    },
  });
  const events = result.events ?? [];
  harvestCursor += events.length;
  return events.map((e) => e.data as unknown as HarvestEventData);
}

export async function pollDeployEvents(limit = 25): Promise<DeployEventData[]> {
  const result = await aptos.queryIndexer<{ events: Array<{ data: unknown }> }>({
    query: {
      query: EVENTS_QUERY,
      variables: { event_type: `${MODULE}::yield_vault::DeployEvent`, limit, offset: deployCursor },
    },
  });
  const events = result.events ?? [];
  deployCursor += events.length;
  return events.map((e) => e.data as unknown as DeployEventData);
}

export async function fetchChainState(
  vaultAddr: string,
  registryAddr: string
): Promise<ChainSnapshot> {
  const vault = await readVaultResource(vaultAddr);
  const registry = await readRegistryResource(registryAddr);
  const nextId = parseInt(registry.next_id);

  const strategyPromises = Array.from({ length: nextId }, (_, i) =>
    readStrategyFromTable(registry.strategies.handle, i)
  );
  const rawStrategies = await Promise.all(strategyPromises);
  const strategies = rawStrategies.filter((s): s is RawStrategy => s !== null && s.active);

  const [harvestEvents, deployEvents] = await Promise.all([
    pollHarvestEvents(),
    pollDeployEvents(),
  ]);

  return {
    vault,
    strategies,
    harvestEvents,
    deployEvents,
    snapshotTs: Math.floor(Date.now() / 1000),
  };
}
