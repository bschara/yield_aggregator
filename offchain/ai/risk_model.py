"""Risk Engine — exposure limits, utilisation scoring, stale bridge detection."""

from __future__ import annotations
import os
from enum import Enum
from pydantic import BaseModel
from typing import List

BRIDGE_TIMEOUT_SEC = int(os.environ.get("BRIDGE_TIMEOUT_SEC", "600"))
UTIL_WARN = 0.80   # 80% deployed → medium risk
UTIL_CRIT = 0.90   # 90% deployed → high risk


class RiskLevel(str, Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"


class StrategyPosition(BaseModel):
    strategyId: str
    capitalAllocated: float  # APT
    maxExposure: float       # APT
    apy: float               # annualised fraction (0.05 = 5%)
    riskScore: float         # 0–1, computed by position_tracker
    lastHarvestTs: int       # unix seconds (0 = never harvested)


class PendingBridge(BaseModel):
    strategyId: str
    nonce: int
    sentAt: int    # unix seconds
    amount: float  # octas


class VaultState(BaseModel):
    tvl: float
    idleAssets: float
    deployedAssets: float
    utilization: float       # 0–1
    strategies: List[StrategyPosition]
    snapshotTs: int
    pendingBridges: List[PendingBridge] = []


def check_overexposed(position: StrategyPosition) -> bool:
    if position.maxExposure <= 0:
        return False
    return position.capitalAllocated > position.maxExposure


def utilization_score(state: VaultState) -> float:
    return min(1.0, state.utilization)


def flag_stale_bridges(
    pending: list[PendingBridge], now_ts: int, timeout_sec: int = BRIDGE_TIMEOUT_SEC
) -> list[PendingBridge]:
    cutoff = now_ts - timeout_sec
    return [b for b in pending if b.sentAt < cutoff]


def overexposed_strategies(positions: list[StrategyPosition]) -> list[str]:
    return [p.strategyId for p in positions if check_overexposed(p)]


def overall_risk(state: VaultState, now_ts: int) -> RiskLevel:
    stale = flag_stale_bridges(state.pendingBridges, now_ts)
    over = overexposed_strategies(state.strategies)
    if stale or over:
        return RiskLevel.CRITICAL
    util = utilization_score(state)
    if util >= UTIL_CRIT:
        return RiskLevel.HIGH
    if util >= UTIL_WARN:
        return RiskLevel.MEDIUM
    return RiskLevel.LOW
