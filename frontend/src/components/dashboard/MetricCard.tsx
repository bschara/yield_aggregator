import type { ReactNode } from "react";
import { Card } from "@/components/common/Card";
import { Spinner } from "@/components/common/Spinner";

interface MetricCardProps {
  label: string;
  value: string;
  sub?: string;
  icon?: ReactNode;
  loading?: boolean;
}

export function MetricCard({ label, value, sub, icon, loading }: MetricCardProps) {
  return (
    <Card>
      <div className="flex items-start justify-between">
        <p className="text-xs text-gray-500 uppercase tracking-wider">{label}</p>
        {icon && <span className="text-gray-600">{icon}</span>}
      </div>
      {loading ? (
        <div className="mt-3 flex items-center gap-2">
          <Spinner size={4} />
          <span className="text-sm text-gray-600">Loading…</span>
        </div>
      ) : (
        <>
          <p className="mt-2 text-2xl font-semibold text-white">{value}</p>
          {sub && <p className="mt-1 text-xs text-gray-500">{sub}</p>}
        </>
      )}
    </Card>
  );
}
