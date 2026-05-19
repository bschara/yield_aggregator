import { PageLayout } from "@/components/layout/PageLayout";
import { MetricCard } from "@/components/dashboard/MetricCard";
import { CapitalBreakdown } from "@/components/dashboard/CapitalBreakdown";
import { PolicyRecommendation } from "@/components/dashboard/PolicyRecommendation";
import { useVaultState, useStrategyList } from "@/hooks/useVaultState";
import { usePolicyDecision } from "@/hooks/usePolicyScore";
import { octasToApt } from "@/lib/aptos";

export function Dashboard() {
  const { data: vault, isLoading: vaultLoading } = useVaultState();
  const { data: strategies } = useStrategyList();
  const { data: decision, isLoading: decisionLoading } = usePolicyDecision();

  const totalApt = vault ? octasToApt(vault.totalAssets) : 0;
  const idleApt = vault ? octasToApt(vault.idleAssets) : 0;
  const deployedApt = vault ? octasToApt(vault.deployedCapital) : 0;
  const activeCount = strategies?.filter((s) => s.active).length ?? 0;

  return (
    <PageLayout title="Dashboard">
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <MetricCard
          label="Total Value Locked"
          value={`${totalApt.toFixed(2)} APT`}
          sub="Across all strategies"
          loading={vaultLoading}
        />
        <MetricCard
          label="Idle Capital"
          value={`${idleApt.toFixed(2)} APT`}
          sub="Available to deploy"
          loading={vaultLoading}
        />
        <MetricCard
          label="Deployed Capital"
          value={`${deployedApt.toFixed(2)} APT`}
          sub="Earning yield"
          loading={vaultLoading}
        />
        <MetricCard
          label="Active Strategies"
          value={activeCount.toString()}
          sub="Across all chains"
          loading={vaultLoading}
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <CapitalBreakdown idleApt={idleApt} deployedApt={deployedApt} />
        <PolicyRecommendation decision={decision} loading={decisionLoading} />
      </div>
    </PageLayout>
  );
}
