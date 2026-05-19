import { useQuery } from "@tanstack/react-query";
import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { fetchUserShares } from "@/lib/aptos";

export function useUserShares() {
  const { account, connected } = useWallet();
  return useQuery({
    queryKey: ["userShares", account?.address.toString()],
    queryFn: () => fetchUserShares(account!.address.toString()),
    enabled: connected && !!account?.address,
    refetchInterval: 12_000,
  });
}
