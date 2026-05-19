import { Badge } from "@/components/common/Badge";

export function RiskBadge({ score }: { score: number }) {
  if (score <= 30) return <Badge label="Low Risk" variant="green" />;
  if (score <= 60) return <Badge label="Med Risk" variant="yellow" />;
  return <Badge label="High Risk" variant="red" />;
}
