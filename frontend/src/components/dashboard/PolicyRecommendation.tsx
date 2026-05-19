import { Card } from "@/components/common/Card";
import { Badge } from "@/components/common/Badge";
import { Spinner } from "@/components/common/Spinner";
import type { PolicyDecision } from "@/lib/policy";

const actionVariant = {
  deploy: "green",
  recall: "yellow",
  harvest: "purple",
  none: "gray",
} as const;

export function PolicyRecommendation({
  decision,
  loading,
}: {
  decision?: PolicyDecision | null;
  loading?: boolean;
}) {
  return (
    <Card>
      <p className="text-xs text-gray-500 uppercase tracking-wider mb-3">Engine Recommendation</p>
      {loading ? (
        <div className="flex items-center gap-2">
          <Spinner size={4} />
          <span className="text-sm text-gray-600">Fetching…</span>
        </div>
      ) : decision ? (
        <div className="flex flex-col gap-2">
          <div className="flex items-center gap-2">
            <Badge
              label={decision.type.toUpperCase()}
              variant={actionVariant[decision.type]}
            />
            {decision.strategyId !== undefined && (
              <span className="text-xs text-gray-400">Strategy #{decision.strategyId}</span>
            )}
            {decision.amountOctas !== undefined && (
              <span className="text-xs text-gray-400">
                {(decision.amountOctas / 1e8).toFixed(2)} APT
              </span>
            )}
          </div>
          <p className="text-sm text-gray-300">{decision.reason}</p>
        </div>
      ) : (
        <p className="text-sm text-gray-500">Engine offline or no data</p>
      )}
    </Card>
  );
}
