import { PageLayout } from "@/components/layout/PageLayout";
import { StrategyCard } from "@/components/strategies/StrategyCard";
import { Spinner } from "@/components/common/Spinner";
import { EmptyState } from "@/components/common/EmptyState";
import { ErrorBanner } from "@/components/common/ErrorBanner";
import { useStrategyList } from "@/hooks/useVaultState";

export function Strategies() {
  const { data: strategies, isLoading, isError } = useStrategyList();

  return (
    <PageLayout title="Strategies">
      {isLoading && (
        <div className="flex items-center gap-2 text-gray-500">
          <Spinner />
          <span className="text-sm">Loading strategies…</span>
        </div>
      )}

      {isError && (
        <ErrorBanner message="Could not fetch strategies. Check that VITE_APTOS_RPC and VITE_REGISTRY_ADDR are set." />
      )}

      {!isLoading && !isError && strategies?.length === 0 && (
        <EmptyState message="No strategies registered yet." />
      )}

      {strategies && strategies.length > 0 && (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {strategies.map((s) => (
            <StrategyCard key={s.id} strategy={s} />
          ))}
        </div>
      )}
    </PageLayout>
  );
}
