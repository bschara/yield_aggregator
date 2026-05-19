import { Card } from "@/components/common/Card";
import { Badge } from "@/components/common/Badge";
import { RiskBadge } from "./RiskBadge";
import type { Strategy } from "@/lib/aptos";
import { octasToApt } from "@/lib/aptos";

export function StrategyCard({ strategy }: { strategy: Strategy }) {
  const deployed = octasToApt(strategy.deployedAmount);
  const maxExp = octasToApt(strategy.maxExposure);
  const utilPct = maxExp > 0 ? (deployed / maxExp) * 100 : 0;

  return (
    <Card>
      <div className="flex items-start justify-between mb-3">
        <div>
          <p className="text-sm font-medium text-white">Strategy #{strategy.id}</p>
          <p className="text-xs text-gray-500 font-mono mt-0.5 truncate w-36">
            {strategy.adapterAddr.slice(0, 10)}…
          </p>
        </div>
        <div className="flex gap-1.5">
          <RiskBadge score={strategy.riskScore} />
          {!strategy.active && <Badge label="Inactive" variant="gray" />}
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3 mt-4">
        <div>
          <p className="text-xs text-gray-500">Deployed</p>
          <p className="text-base font-semibold text-white">{deployed.toFixed(2)} APT</p>
        </div>
        <div>
          <p className="text-xs text-gray-500">Max Exposure</p>
          <p className="text-base font-semibold text-gray-300">{maxExp.toFixed(2)} APT</p>
        </div>
      </div>

      <div className="mt-4">
        <div className="flex justify-between text-xs text-gray-500 mb-1">
          <span>Utilization</span>
          <span>{utilPct.toFixed(1)}%</span>
        </div>
        <div className="w-full h-1.5 rounded-full bg-gray-800">
          <div
            className={`h-full rounded-full transition-all duration-500 ${
              utilPct > 90 ? "bg-red-500" : utilPct > 70 ? "bg-yellow-500" : "bg-brand-500"
            }`}
            style={{ width: `${Math.min(utilPct, 100)}%` }}
          />
        </div>
      </div>

      <div className="mt-3">
        <p className="text-xs text-gray-500">Risk Score</p>
        <p className="text-sm text-gray-300">{strategy.riskScore} / 100</p>
      </div>
    </Card>
  );
}
