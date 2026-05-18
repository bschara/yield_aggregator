"""Yield Engine — scores strategies and decides deploy/harvest actions."""

from __future__ import annotations
import os
from typing import Optional, TYPE_CHECKING

if TYPE_CHECKING:
    from .risk_model import StrategyPosition

MIN_DEPLOY_APT = float(os.environ.get("MIN_DEPLOY_AMOUNT", "100000000")) / 1e8
HARVEST_MIN_INTERVAL = int(os.environ.get("HARVEST_MIN_INTERVAL_SEC", "3600"))
RECALL_APY_THRESHOLD = 0.05  # below 5% APY → candidate for recall


def score_strategy(position: "StrategyPosition") -> float:
    """Higher score = better deployment target.

    Combines APY reward with penalties for risk and proximity to max exposure.
    """
    if position.maxExposure <= 0:
        return 0.0
    headroom = max(0.0, 1.0 - position.capitalAllocated / position.maxExposure)
    risk_discount = 1.0 - position.riskScore * 0.5
    return position.apy * headroom * risk_discount


def should_harvest(position: "StrategyPosition", now_ts: int) -> bool:
    """True when the strategy has capital and enough time has elapsed since last harvest."""
    if position.capitalAllocated <= 0:
        return False
    elapsed = now_ts - position.lastHarvestTs
    return elapsed >= HARVEST_MIN_INTERVAL


def best_deploy_target(
    positions: list["StrategyPosition"], idle_amount: float
) -> Optional[str]:
    """Pick the strategy ID to deploy idle capital to, or None."""
    if idle_amount < MIN_DEPLOY_APT:
        return None
    candidates = [
        p for p in positions
        if p.capitalAllocated < p.maxExposure and p.riskScore < 0.9
    ]
    if not candidates:
        return None
    best = max(candidates, key=score_strategy)
    return best.strategyId if score_strategy(best) > 0 else None


def amount_to_deploy(position: "StrategyPosition", idle_apt: float) -> float:
    """How much APT to deploy (capped at headroom, keeps 20% idle buffer)."""
    headroom = position.maxExposure - position.capitalAllocated
    return min(idle_apt * 0.8, headroom)


def underperforming_strategies(positions: list["StrategyPosition"]) -> list[str]:
    """Strategy IDs whose APY has dropped below the recall threshold."""
    return [
        p.strategyId
        for p in positions
        if p.capitalAllocated > 0 and 0 < p.apy < RECALL_APY_THRESHOLD
    ]
