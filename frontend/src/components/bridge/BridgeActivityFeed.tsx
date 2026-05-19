import type { BridgeEvent } from "@/lib/ethereum";
import { Badge } from "@/components/common/Badge";

const ACTION_LABELS: Record<number, string> = {
  1: "DEPLOY",
  2: "RECALL",
  3: "HARVEST",
  4: "COMPLETE",
};

export function BridgeActivityFeed({ events }: { events: BridgeEvent[] }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="text-xs text-gray-500 border-b border-gray-800">
            <th className="text-left pb-2 pr-4">Direction</th>
            <th className="text-left pb-2 pr-4">Action</th>
            <th className="text-left pb-2 pr-4">Strategy</th>
            <th className="text-left pb-2 pr-4">Amount (APT)</th>
            <th className="text-left pb-2 pr-4">Block</th>
            <th className="text-left pb-2">Tx</th>
          </tr>
        </thead>
        <tbody>
          {events.map((ev, i) => (
            <tr key={i} className="border-b border-gray-800/50 last:border-0">
              <td className="py-2.5 pr-4">
                <Badge
                  label={ev.type === "incoming" ? "← In" : "Out →"}
                  variant={ev.type === "incoming" ? "green" : "purple"}
                />
              </td>
              <td className="py-2.5 pr-4 text-gray-300">
                {ACTION_LABELS[ev.action] ?? ev.action}
              </td>
              <td className="py-2.5 pr-4 text-gray-300">#{ev.strategyId.toString()}</td>
              <td className="py-2.5 pr-4 text-gray-300">
                {(Number(ev.amount) / 1e8).toFixed(4)}
              </td>
              <td className="py-2.5 pr-4 text-gray-500">{ev.blockNumber}</td>
              <td className="py-2.5 font-mono text-gray-500 text-xs">
                {ev.txHash.slice(0, 10)}…
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
