// Mirrors YieldAggregator::strategy_executor::ExecutionIntent
// Action enum ordinals must stay in sync with Move:
//   Deposit=0, Withdraw=1, Harvest=2, Exit=3
export const Action = {
  Deposit: 0,
  Withdraw: 1,
  Harvest: 2,
  Exit: 3,
} as const;
export type ActionType = (typeof Action)[keyof typeof Action];

export interface ExecutionIntent {
  strategy_id: number;
  action: ActionType;
  amount: number;        // octas (u64)
  fee_amount: number;    // octas (u64)
  target_chain: number | null; // option::Option<u64>: null → None
  nonce: number;
}

let nonceCounter = Math.floor(Date.now() / 1000); // monotonic, survives restarts

export function nextNonce(): number {
  return nonceCounter++;
}

export function buildDeployIntent(
  strategyId: number,
  amountOctas: number,
  feeOctas = 0
): ExecutionIntent {
  return {
    strategy_id: strategyId,
    action: Action.Deposit,
    amount: amountOctas,
    fee_amount: feeOctas,
    target_chain: null,
    nonce: nextNonce(),
  };
}

export function buildRecallIntent(
  strategyId: number,
  amountOctas: number,
  feeOctas = 0
): ExecutionIntent {
  return {
    strategy_id: strategyId,
    action: Action.Withdraw,
    amount: amountOctas,
    fee_amount: feeOctas,
    target_chain: null,
    nonce: nextNonce(),
  };
}

export function buildHarvestIntent(strategyId: number, feeOctas = 0): ExecutionIntent {
  return {
    strategy_id: strategyId,
    action: Action.Harvest,
    amount: 0,
    fee_amount: feeOctas,
    target_chain: null,
    nonce: nextNonce(),
  };
}

export function buildExitIntent(
  strategyId: number,
  amountOctas: number,
  feeOctas = 0
): ExecutionIntent {
  return {
    strategy_id: strategyId,
    action: Action.Exit,
    amount: amountOctas,
    fee_amount: feeOctas,
    target_chain: null,
    nonce: nextNonce(),
  };
}
