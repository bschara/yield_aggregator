import { useQuery } from "@tanstack/react-query";
import { fetchPendingBridges } from "@/lib/ethereum";

export function useBridgeStatus() {
  return useQuery({
    queryKey: ["bridgeStatus"],
    queryFn: fetchPendingBridges,
    refetchInterval: 15_000,
    retry: 1,
  });
}
