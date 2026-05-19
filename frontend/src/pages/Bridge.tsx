import { PageLayout } from "@/components/layout/PageLayout";
import { Card } from "@/components/common/Card";
import { Spinner } from "@/components/common/Spinner";
import { EmptyState } from "@/components/common/EmptyState";
import { ErrorBanner } from "@/components/common/ErrorBanner";
import { BridgeActivityFeed } from "@/components/bridge/BridgeActivityFeed";
import { useBridgeStatus } from "@/hooks/useBridgeStatus";

export function Bridge() {
  const { data: events, isLoading, isError } = useBridgeStatus();

  return (
    <PageLayout title="Bridge Activity">
      <p className="text-sm text-gray-500 mb-6">
        Recent cross-chain messages between Aptos and Ethereum via LayerZero (last 2000 blocks).
      </p>

      {isLoading && (
        <div className="flex items-center gap-2 text-gray-500">
          <Spinner />
          <span className="text-sm">Fetching bridge events…</span>
        </div>
      )}

      {isError && (
        <ErrorBanner message="Could not fetch bridge events. Check that VITE_ETH_RPC and VITE_VAULT_OFT_ADDR are set." />
      )}

      {!isLoading && !isError && (
        <Card>
          {events && events.length > 0 ? (
            <BridgeActivityFeed events={events} />
          ) : (
            <EmptyState message="No bridge events found in recent blocks." />
          )}
        </Card>
      )}
    </PageLayout>
  );
}
