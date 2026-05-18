"""Rebalance Policy — combines Yield Engine + Risk Engine into a single Action."""

from __future__ import annotations
import time
from typing import Optional
from pydantic import BaseModel

from .risk_model import VaultState, flag_stale_bridges, overexposed_strategies
from .yield_model import should_harvest, best_deploy_target, amount_to_deploy, underperforming_strategies

OCTAS_PER_APT = 1e8


class Action(BaseModel):
    type: str                          # "harvest" | "deploy" | "recall" | "none"
    strategyId: Optional[str] = None
    amountOctas: Optional[int] = None
    reason: str = ""


def decide(state: VaultState) -> Action:
    """Return the single highest-priority action to execute this tick.

    Priority order:
      1. Recall over-exposed strategies  (risk guard)
      2. Recall strategies with stale bridge messages  (stuck-capital guard)
      3. Recall under-performing strategies  (yield optimisation)
      4. Deploy idle capital to best target  (yield maximisation)
      5. Harvest mature strategies  (yield collection)
      6. No-op
    """
    now_ts = int(time.time())

    # 1. Over-exposure guard
    overexposed = overexposed_strategies(state.strategies)
    if overexposed:
        sid = overexposed[0]
        pos = next(p for p in state.strategies if p.strategyId == sid)
        excess = pos.capitalAllocated - pos.maxExposure
        return Action(
            type="recall",
            strategyId=sid,
            amountOctas=int(excess * OCTAS_PER_APT),
            reason=f"strategy {sid} over max_exposure by {excess:.4f} APT",
        )

    # 2. Stale bridge guard
    stale = flag_stale_bridges(state.pendingBridges, now_ts)
    if stale:
        b = stale[0]
        return Action(
            type="recall",
            strategyId=b.strategyId,
            amountOctas=int(b.amount),
            reason=f"bridge nonce={b.nonce} stale for {now_ts - b.sentAt}s",
        )

    # 3. Under-performing recall
    underperforming = underperforming_strategies(state.strategies)
    if underperforming:
        sid = underperforming[0]
        pos = next(p for p in state.strategies if p.strategyId == sid)
        return Action(
            type="recall",
            strategyId=sid,
            amountOctas=int(pos.capitalAllocated * OCTAS_PER_APT),
            reason=f"strategy {sid} APY {pos.apy:.2%} below threshold",
        )

    # 4. Deploy idle capital
    target_id = best_deploy_target(state.strategies, state.idleAssets)
    if target_id is not None:
        pos = next(p for p in state.strategies if p.strategyId == target_id)
        deploy_apt = amount_to_deploy(pos, state.idleAssets)
        return Action(
            type="deploy",
            strategyId=target_id,
            amountOctas=int(deploy_apt * OCTAS_PER_APT),
            reason=f"deploy {deploy_apt:.4f} APT to strategy {target_id} (APY {pos.apy:.2%})",
        )

    # 5. Harvest mature strategies
    for pos in state.strategies:
        if should_harvest(pos, now_ts):
            return Action(
                type="harvest",
                strategyId=pos.strategyId,
                amountOctas=0,
                reason=f"harvest strategy {pos.strategyId} (last={pos.lastHarvestTs})",
            )

    return Action(type="none", reason="all checks passed, nothing to do")
