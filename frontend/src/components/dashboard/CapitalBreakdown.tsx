import { Card } from "@/components/common/Card";

interface CapitalBreakdownProps {
  idleApt: number;
  deployedApt: number;
}

export function CapitalBreakdown({ idleApt, deployedApt }: CapitalBreakdownProps) {
  const total = idleApt + deployedApt;
  const deployedPct = total > 0 ? (deployedApt / total) * 100 : 0;
  const idlePct = 100 - deployedPct;

  return (
    <Card>
      <p className="text-xs text-gray-500 uppercase tracking-wider mb-4">Capital Allocation</p>
      <div className="w-full h-3 rounded-full bg-gray-800 overflow-hidden mb-4">
        <div
          className="h-full bg-brand-600 rounded-full transition-all duration-500"
          style={{ width: `${deployedPct}%` }}
        />
      </div>
      <div className="flex justify-between text-sm">
        <div>
          <p className="text-brand-500 font-semibold">{deployedApt.toFixed(2)} APT</p>
          <p className="text-xs text-gray-500">Deployed ({deployedPct.toFixed(1)}%)</p>
        </div>
        <div className="text-right">
          <p className="text-gray-300 font-semibold">{idleApt.toFixed(2)} APT</p>
          <p className="text-xs text-gray-500">Idle ({idlePct.toFixed(1)}%)</p>
        </div>
      </div>
    </Card>
  );
}
