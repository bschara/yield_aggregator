const POLICY_URL = import.meta.env.VITE_POLICY_SERVER_URL ?? "http://localhost:8001";

export interface PolicyDecision {
  type: "deploy" | "recall" | "harvest" | "none";
  strategyId?: number;
  amountOctas?: number;
  reason: string;
}

export interface PolicyStrategyScore {
  id: number;
  apy: number;
  riskScore: number;
  deployedApt: number;
}

export async function fetchPolicyDecision(vaultState: object): Promise<PolicyDecision | null> {
  try {
    const res = await fetch(`${POLICY_URL}/decide`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ vault_state: vaultState, pending_bridges: [] }),
      signal: AbortSignal.timeout(5000),
    });
    if (!res.ok) return null;
    return res.json();
  } catch {
    return null;
  }
}

export async function checkPolicyHealth(): Promise<boolean> {
  try {
    const res = await fetch(`${POLICY_URL}/health`, { signal: AbortSignal.timeout(3000) });
    return res.ok;
  } catch {
    return false;
  }
}
