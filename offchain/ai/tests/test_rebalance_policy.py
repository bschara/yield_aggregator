"""Unit tests for rebalance_policy.py — decision tree in priority order."""

import pytest
from ..risk_model import StrategyPosition, PendingBridge, VaultState
from ..rebalance_policy import decide
from ..yield_model import MIN_DEPLOY_APT, HARVEST_MIN_INTERVAL, RECALL_APY_THRESHOLD


# ── Helpers ───────────────────────────────────────────────────────────────────

import time as _time

# Use a well-known timestamp far in the future so harvest/stale checks pass
# without needing to mock time.time() in every test.
_EPOCH_VERY_OLD = 0        # last_harvest=0 → always old enough to harvest
_EPOCH_NOW_APPROX = int(_time.time())


def make_pos(
    sid: str = "0",
    allocated: float = 50.0,
    max_exp: float = 100.0,
    apy: float = 0.10,
    risk: float = 0.2,
    last_harvest: int = _EPOCH_VERY_OLD,
) -> StrategyPosition:
    return StrategyPosition(
        strategyId=sid,
        capitalAllocated=allocated,
        maxExposure=max_exp,
        apy=apy,
        riskScore=risk,
        lastHarvestTs=last_harvest,
    )


def make_state(
    strategies: list,
    idle: float = 10.0,
    pending: list | None = None,
) -> VaultState:
    deployed = sum(p.capitalAllocated for p in strategies)
    tvl = idle + deployed
    return VaultState(
        tvl=tvl,
        idleAssets=idle,
        deployedAssets=deployed,
        utilization=deployed / tvl if tvl > 0 else 0.0,
        strategies=strategies,
        snapshotTs=_EPOCH_NOW_APPROX,
        pendingBridges=pending or [],
    )


# ── Priority 1: over-exposure recall ─────────────────────────────────────────

class TestOverExposureGuard:
    def test_recalls_overexposed_strategy(self):
        over = make_pos("over", allocated=150.0, max_exp=100.0)
        state = make_state([over], idle=0.0)
        action = decide(state)
        assert action.type == "recall"
        assert action.strategyId == "over"
        assert action.amountOctas == pytest.approx(50 * 1e8, rel=1e-6)

    def test_over_exposure_beats_stale_bridge(self):
        over = make_pos("over", allocated=110.0, max_exp=100.0)
        stale = PendingBridge(strategyId="stale", nonce=1, sentAt=0, amount=1000.0)
        state = make_state([over], pending=[stale])
        action = decide(state)
        assert action.type == "recall"
        assert action.strategyId == "over"


# ── Priority 2: stale bridge recall ──────────────────────────────────────────

class TestStaleBridgeGuard:
    def test_recalls_strategy_with_stale_bridge(self):
        # sentAt=0 means always stale
        stale = PendingBridge(strategyId="bridged", nonce=1, sentAt=0, amount=int(5 * 1e8))
        normal = make_pos("ok", allocated=50.0, max_exp=100.0, apy=0.15)
        state = make_state([normal], pending=[stale])
        action = decide(state)
        assert action.type == "recall"
        assert action.strategyId == "bridged"

    def test_fresh_bridge_does_not_trigger_recall(self):
        fresh = PendingBridge(
            strategyId="bridged", nonce=1,
            sentAt=_EPOCH_NOW_APPROX - 30,  # 30 seconds ago, well within timeout
            amount=int(5 * 1e8),
        )
        normal = make_pos("ok", allocated=50.0, max_exp=100.0, apy=0.0)
        state = make_state([normal], idle=0.0, pending=[fresh])
        action = decide(state)
        assert action.type != "recall" or action.strategyId != "bridged"


# ── Priority 3: underperforming recall ───────────────────────────────────────

class TestUnderperformingRecall:
    def test_recalls_low_apy_strategy(self):
        bad = make_pos("bad", allocated=50.0, apy=RECALL_APY_THRESHOLD * 0.5)
        state = make_state([bad], idle=0.0)
        action = decide(state)
        assert action.type == "recall"
        assert action.strategyId == "bad"

    def test_does_not_recall_zero_apy_strategy(self):
        # apy=0 means no data yet — don't recall blindly
        new_strat = make_pos("new", allocated=50.0, apy=0.0)
        state = make_state([new_strat], idle=0.0)
        action = decide(state)
        assert not (action.type == "recall" and action.strategyId == "new")


# ── Priority 4: deploy idle capital ──────────────────────────────────────────

class TestDeployIdle:
    def test_deploys_idle_capital_to_best_target(self):
        target = make_pos("target", allocated=0.0, max_exp=200.0, apy=0.15, risk=0.2)
        idle = MIN_DEPLOY_APT * 2
        state = make_state([target], idle=idle)
        action = decide(state)
        assert action.type == "deploy"
        assert action.strategyId == "target"
        assert action.amountOctas is not None and action.amountOctas > 0

    def test_no_deploy_when_idle_below_minimum(self):
        target = make_pos("target", allocated=0.0, max_exp=200.0, apy=0.15)
        state = make_state([target], idle=MIN_DEPLOY_APT * 0.1)
        action = decide(state)
        assert action.type != "deploy"


# ── Priority 5: harvest ───────────────────────────────────────────────────────

class TestHarvest:
    def test_harvests_mature_strategy(self):
        # lastHarvestTs=0 → always old enough
        harvestable = make_pos("harvest_me", allocated=50.0, apy=0.10, last_harvest=0)
        # No idle capital → skips deploy, reaches harvest
        state = make_state([harvestable], idle=0.0)
        action = decide(state)
        assert action.type == "harvest"
        assert action.strategyId == "harvest_me"

    def test_no_harvest_when_recently_done(self):
        recent = make_pos(
            "recent", allocated=50.0, apy=0.10,
            last_harvest=_EPOCH_NOW_APPROX - 30,  # just 30s ago
        )
        state = make_state([recent], idle=0.0)
        action = decide(state)
        assert action.type != "harvest"


# ── Priority 6: no-op ─────────────────────────────────────────────────────────

class TestNoOp:
    def test_returns_none_when_all_checks_pass(self):
        # Healthy strategy, recently harvested, no idle capital
        healthy = make_pos(
            "healthy", allocated=50.0, max_exp=100.0, apy=0.12,
            last_harvest=_EPOCH_NOW_APPROX - 30,
        )
        state = make_state([healthy], idle=0.0)
        action = decide(state)
        assert action.type == "none"
