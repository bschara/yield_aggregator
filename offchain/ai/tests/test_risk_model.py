"""Unit tests for risk_model.py — all pure functions."""

import pytest
from ..risk_model import (
    RiskLevel,
    StrategyPosition,
    PendingBridge,
    VaultState,
    check_overexposed,
    utilization_score,
    flag_stale_bridges,
    overexposed_strategies,
    overall_risk,
)


# ── Fixtures ─────────────────────────────────────────────────────────────────

def make_position(
    sid: str = "0",
    allocated: float = 50.0,
    max_exp: float = 100.0,
    apy: float = 0.10,
    risk: float = 0.3,
    last_harvest: int = 0,
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
    utilization: float = 0.5,
    strategies: list | None = None,
    pending: list | None = None,
) -> VaultState:
    tvl = 100.0
    return VaultState(
        tvl=tvl,
        idleAssets=tvl * (1 - utilization),
        deployedAssets=tvl * utilization,
        utilization=utilization,
        strategies=strategies or [make_position()],
        snapshotTs=1_000_000,
        pendingBridges=pending or [],
    )


# ── check_overexposed ─────────────────────────────────────────────────────────

class TestCheckOverexposed:
    def test_not_overexposed_when_under_max(self):
        assert check_overexposed(make_position(allocated=50.0, max_exp=100.0)) is False

    def test_overexposed_when_over_max(self):
        assert check_overexposed(make_position(allocated=110.0, max_exp=100.0)) is True

    def test_exact_equality_is_not_overexposed(self):
        assert check_overexposed(make_position(allocated=100.0, max_exp=100.0)) is False

    def test_zero_max_exposure_is_not_overexposed(self):
        # maxExposure=0 means the strategy is not registered — guard avoids div-by-zero
        assert check_overexposed(make_position(allocated=10.0, max_exp=0.0)) is False


# ── utilization_score ─────────────────────────────────────────────────────────

class TestUtilizationScore:
    def test_low_utilization(self):
        assert utilization_score(make_state(utilization=0.5)) == pytest.approx(0.5)

    def test_full_utilization(self):
        assert utilization_score(make_state(utilization=1.0)) == pytest.approx(1.0)

    def test_over_full_clamped_to_one(self):
        # Utilization > 1 can happen transiently; clamp prevents score > 1.
        assert utilization_score(make_state(utilization=1.5)) == pytest.approx(1.0)

    def test_zero_utilization(self):
        assert utilization_score(make_state(utilization=0.0)) == pytest.approx(0.0)


# ── flag_stale_bridges ────────────────────────────────────────────────────────

class TestFlagStaleBridges:
    NOW = 1_001_000  # arbitrary "current" timestamp

    def _bridge(self, nonce: int, sent_at: int) -> PendingBridge:
        return PendingBridge(strategyId="0", nonce=nonce, sentAt=sent_at, amount=100.0)

    def test_stale_bridge_is_returned(self):
        stale = self._bridge(1, self.NOW - 700)  # 700s ago, timeout=600s
        result = flag_stale_bridges([stale], self.NOW, timeout_sec=600)
        assert len(result) == 1
        assert result[0].nonce == 1

    def test_fresh_bridge_is_not_returned(self):
        fresh = self._bridge(2, self.NOW - 100)  # only 100s ago
        result = flag_stale_bridges([fresh], self.NOW, timeout_sec=600)
        assert result == []

    def test_exactly_at_cutoff_is_not_stale(self):
        # sentAt == cutoff means NOT stale (strict less-than)
        at_cutoff = self._bridge(3, self.NOW - 600)
        result = flag_stale_bridges([at_cutoff], self.NOW, timeout_sec=600)
        assert result == []

    def test_mixed_returns_only_stale(self):
        stale = self._bridge(10, self.NOW - 900)
        fresh = self._bridge(11, self.NOW - 200)
        result = flag_stale_bridges([stale, fresh], self.NOW, timeout_sec=600)
        assert len(result) == 1
        assert result[0].nonce == 10

    def test_empty_list(self):
        assert flag_stale_bridges([], self.NOW) == []


# ── overexposed_strategies ────────────────────────────────────────────────────

class TestOverexposedStrategies:
    def test_returns_empty_when_none_overexposed(self):
        positions = [make_position("0", 50, 100), make_position("1", 80, 100)]
        assert overexposed_strategies(positions) == []

    def test_returns_id_of_overexposed_strategy(self):
        positions = [make_position("0", 50, 100), make_position("1", 120, 100)]
        result = overexposed_strategies(positions)
        assert result == ["1"]

    def test_returns_multiple_overexposed(self):
        positions = [make_position("0", 110, 100), make_position("1", 200, 100)]
        result = overexposed_strategies(positions)
        assert set(result) == {"0", "1"}


# ── overall_risk ──────────────────────────────────────────────────────────────

class TestOverallRisk:
    NOW = 2_000_000

    def test_low_risk_clean_state(self):
        assert overall_risk(make_state(utilization=0.5), self.NOW) == RiskLevel.LOW

    def test_medium_risk_at_80_percent_utilization(self):
        assert overall_risk(make_state(utilization=0.80), self.NOW) == RiskLevel.MEDIUM

    def test_high_risk_at_90_percent_utilization(self):
        assert overall_risk(make_state(utilization=0.90), self.NOW) == RiskLevel.HIGH

    def test_critical_risk_with_stale_bridge(self):
        stale_bridge = PendingBridge(
            strategyId="0", nonce=1, sentAt=self.NOW - 700, amount=100.0
        )
        state = make_state(pending=[stale_bridge])
        assert overall_risk(state, self.NOW) == RiskLevel.CRITICAL

    def test_critical_risk_with_overexposed_strategy(self):
        over = make_position("0", allocated=150.0, max_exp=100.0)
        state = make_state(strategies=[over])
        assert overall_risk(state, self.NOW) == RiskLevel.CRITICAL

    def test_critical_beats_high_utilization(self):
        # Even at 95% utilization, a stale bridge still triggers CRITICAL
        stale = PendingBridge(strategyId="0", nonce=1, sentAt=self.NOW - 700, amount=100.0)
        state = make_state(utilization=0.95, pending=[stale])
        assert overall_risk(state, self.NOW) == RiskLevel.CRITICAL
