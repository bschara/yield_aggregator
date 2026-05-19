import { Aptos, AptosConfig, Network } from "@aptos-labs/ts-sdk";

const RPC = import.meta.env.VITE_APTOS_RPC ?? "https://fullnode.devnet.aptoslabs.com/v1";
export const MODULE_ADDR = import.meta.env.VITE_APTOS_MODULE_ADDR ?? "";
export const VAULT_ADDR = import.meta.env.VITE_VAULT_ADDR ?? "";
export const REGISTRY_ADDR = import.meta.env.VITE_REGISTRY_ADDR ?? "";

const config = new AptosConfig({ network: Network.DEVNET, fullnode: RPC });
export const aptos = new Aptos(config);

export interface VaultState {
  totalAssets: bigint;
  idleAssets: bigint;
  deployedCapital: bigint;
  shareSupply: bigint;
}

export interface Strategy {
  id: number;
  adapterAddr: string;
  maxExposure: bigint;
  riskScore: number;
  active: boolean;
  deployedAmount: bigint;
}

export async function fetchVaultState(): Promise<VaultState> {
  const resource = await aptos.getAccountResource({
    accountAddress: VAULT_ADDR,
    resourceType: `${MODULE_ADDR}::vault::Vault`,
  });
  const d = resource as Record<string, unknown>;
  return {
    totalAssets: BigInt((d.total_assets as string) ?? "0"),
    idleAssets: BigInt((d.idle_assets as string) ?? "0"),
    deployedCapital: BigInt((d.deployed_capital as string) ?? "0"),
    shareSupply: BigInt((d.share_supply as string) ?? "0"),
  };
}

export async function fetchStrategyList(): Promise<Strategy[]> {
  const resource = await aptos.getAccountResource({
    accountAddress: REGISTRY_ADDR,
    resourceType: `${MODULE_ADDR}::strategy_registry::Registry`,
  });
  const d = resource as Record<string, unknown>;
  const strategies = (d.strategies as unknown[]) ?? [];
  return strategies.map((s, i) => {
    const st = s as Record<string, unknown>;
    return {
      id: i,
      adapterAddr: (st.adapter as string) ?? "",
      maxExposure: BigInt((st.max_exposure as string) ?? "0"),
      riskScore: Number(st.risk ?? 0),
      active: Boolean(st.active ?? false),
      deployedAmount: BigInt((st.deployed_amount as string) ?? "0"),
    };
  });
}

export async function fetchUserShares(walletAddr: string): Promise<bigint> {
  try {
    const resource = await aptos.getAccountResource({
      accountAddress: walletAddr,
      resourceType: `${MODULE_ADDR}::vault::ShareBalance`,
    });
    const d = resource as Record<string, unknown>;
    return BigInt((d.shares as string) ?? "0");
  } catch {
    return 0n;
  }
}

export function buildDepositPayload(amountOctas: bigint) {
  return {
    function: `${MODULE_ADDR}::vault::deposit_entry` as `${string}::${string}::${string}`,
    typeArguments: [] as [],
    functionArguments: [amountOctas.toString(), VAULT_ADDR],
  };
}

export function buildWithdrawPayload(depositObjAddr: string) {
  return {
    function: `${MODULE_ADDR}::vault::withdraw` as `${string}::${string}::${string}`,
    typeArguments: [] as [],
    functionArguments: [depositObjAddr, VAULT_ADDR],
  };
}

export function octasToApt(octas: bigint): number {
  return Number(octas) / 1e8;
}
