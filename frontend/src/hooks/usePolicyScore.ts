import { useQuery } from "@tanstack/react-query";
import { checkPolicyHealth, fetchPolicyDecision } from "@/lib/policy";
import { useVaultState } from "./useVaultState";

export function usePolicyHealth() {
  return useQuery({
    queryKey: ["policyHealth"],
    queryFn: checkPolicyHealth,
    refetchInterval: 30_000,
  });
}

export function usePolicyDecision() {
  const { data: vaultState } = useVaultState();
  return useQuery({
    queryKey: ["policyDecision", vaultState],
    queryFn: () => fetchPolicyDecision(vaultState ?? {}),
    enabled: !!vaultState,
    refetchInterval: 30_000,
  });
}
