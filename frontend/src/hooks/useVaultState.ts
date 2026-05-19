import { useQuery } from "@tanstack/react-query";
import { fetchVaultState, fetchStrategyList } from "@/lib/aptos";

export function useVaultState() {
  return useQuery({
    queryKey: ["vaultState"],
    queryFn: fetchVaultState,
    refetchInterval: 10_000,
    retry: 2,
  });
}

export function useStrategyList() {
  return useQuery({
    queryKey: ["strategyList"],
    queryFn: fetchStrategyList,
    refetchInterval: 15_000,
    retry: 2,
  });
}
