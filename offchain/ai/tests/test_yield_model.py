"""Unit tests for yield_model.py — all pure functions."""

import pytest
from ..risk_model import StrategyPosition
from ..yield_model import (
    score_strategy,
    should_harvest,
    best_deploy_target,
    amount_to_deploy,
    underperforming_strategies,
    MIN_DEPLOY_APT,
    HARVEST_MIN_INTERVAL,
    RECALL_APY_THRESHOLD,
)


# ── Fixtures ─────────────────────────────────────────────────────────────────

def make_pos(
    sid: str = "0",
    allocated: float = 50.0,
    max_exp: float = 100.0,
    apy: float = 0.10,
    risk: float = 0.2,
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


# ── score_strategy ────────────────────────────────────────────────────────────

class TestScoreStrategy:
    def test_zero_when_max_exposure_is_zero(self):
        assert score_strategy(make_pos(max_exp=0.0)) == 0.0

    def test_zero_when_fully_allocated(self):
        assert score_strategy(make_pos(allocated=100.0, max_exp=100.0)) == pytest.approx(0.0)

    def test_correct_formula(self):
        # headroom = 1 - 50/100 = 0.5
        # risk_discount = 1 - 0.2 * 0.5 = 0.9
        # score = 0.10 * 0.5 * 0.9 = 0.045
        pos = make_pos(allocated=50.0, max_exp=100.0, apy=0.10, risk=0.2)
        assert score_strategy(pos) == pytest.approx(0.045)

    def test_higher_apy_gives_higher_score(self):
        low_apy = make_pos(apy=0.05)
        high_apy = make_pos(apy=0.20)
        assert score_strategy(high_apy) > score_strategy(low_apy)

    def test_higher_risk_reduces_score(self):
        low_risk = make_pos(risk=0.1)
        high_risk = make_pos(risk=0.8)
        assert score_strategy(low_risk) > score_strategy(high_risk)


# ── should_harvest ────────────────────────────────────────────────────────────

class TestShouldHarvest:
    NOW = 10_000_000

    def test_true_when_interval_elapsed_and_has_capital(self):
        pos = make_pos(allocated=10.0, last_harvest=self.NOW - HARVEST_MIN_INTERVAL)
        assert should_harvest(pos, self.NOW) is True

    def test_true_when_never_harvested_and_has_capital(self):
        pos = make_pos(allocated=10.0, last_harvest=0)
        assert should_harvest(pos, self.NOW) is True

    def test_false_when_recently_harvested(self):
        pos = make_pos(allocated=10.0, last_harvest=self.NOW - 100)  # 100s ago
        assert should_harvest(pos, self.NOW) is False

    def test_false_when_no_capital_deployed(self):
        pos = make_pos(allocated=0.0, last_harvest=0)
        assert should_harvest(pos, self.NOW) is False

    def test_exact_interval_triggers_harvest(self):
        pos = make_pos(allocated=5.0, last_harvest=self.NOW - HARVEST_MIN_INTERVAL)
        assert should_harvest(pos, self.NOW) is True


# ── best_deploy_target ────────────────────────────────────────────────────────

class TestBestDeployTarget:
    def test_returns_none_when_idle_below_minimum(self):
        positions = [make_pos("0", allocated=0, max_exp=100)]
        assert best_deploy_target(positions, MIN_DEPLOY_APT * 0.5) is None

    def test_returns_highest_scoring_strategy(self):
        p_low = make_pos("low", allocated=50.0, max_exp=100.0, apy=0.05)
        p_high = make_pos("high", allocated=10.0, max_exp=100.0, apy=0.20)
        result = best_deploy_target([p_low, p_high], MIN_DEPLOY_APT * 2)
        assert result == "high"

    def test_skips_strategies_with_no_headroom(self):
        full = make_pos("full", allocated=100.0, max_exp=100.0, apy=0.50)
        partial = make_pos("partial", allocated=50.0, max_exp=100.0, apy=0.10)
        result = best_deploy_target([full, partial], MIN_DEPLOY_APT * 2)
        assert result == "partial"

    def test_skips_strategies_with_risk_score_09_or_above(self):
        risky = make_pos("risky", allocated=0.0, max_exp=100.0, apy=0.99, risk=0.9)
        safe = make_pos("safe", allocated=0.0, max_exp=100.0, apy=0.10, risk=0.3)
        result = best_deploy_target([risky, safe], MIN_DEPLOY_APT * 2)
        assert result == "safe"

    def test_returns_none_when_all_candidates_score_zero(self):
        # All strategies are fully allocated — score = 0
        full = make_pos("0", allocated=100.0, max_exp=100.0, apy=0.20)
        assert best_deploy_target([full], MIN_DEPLOY_APT * 2) is None

    def test_returns_none_with_empty_positions(self):
        assert best_deploy_target([], MIN_DEPLOY_APT * 2) is None


# ── amount_to_deploy ──────────────────────────────────────────────────────────

class TestAmountToDeploy:
    def test_respects_80_percent_idle_cap(self):
        pos = make_pos(allocated=0.0, max_exp=1000.0)
        idle = 100.0
        # min(100 * 0.8, 1000 - 0) = min(80, 1000) = 80
        assert amount_to_deploy(pos, idle) == pytest.approx(80.0)

    def test_respects_headroom_cap(self):
        pos = make_pos(allocated=90.0, max_exp=100.0)
        idle = 500.0
        # headroom = 100 - 90 = 10; min(500 * 0.8, 10) = min(400, 10) = 10
        assert amount_to_deploy(pos, idle) == pytest.approx(10.0)

    def test_zero_idle_deploys_nothing(self):
        pos = make_pos(allocated=0.0, max_exp=100.0)
        assert amount_to_deploy(pos, 0.0) == pytest.approx(0.0)


# ── underperforming_strategies ────────────────────────────────────────────────

class TestUnderperformingStrategies:
    def test_returns_empty_for_healthy_strategies(self):
        positions = [make_pos("0", apy=0.10), make_pos("1", apy=0.20)]
        assert underperforming_strategies(positions) == []

    def test_returns_id_when_apy_below_threshold(self):
        under = make_pos("under", allocated=50.0, apy=RECALL_APY_THRESHOLD * 0.5)
        result = underperforming_strategies([under])
        assert result == ["under"]

    def test_skips_strategies_with_no_capital(self):
        # No capital deployed → not a candidate for recall
        no_cap = make_pos("zero", allocated=0.0, apy=0.01)
        assert underperforming_strategies([no_cap]) == []

    def test_skips_strategies_with_zero_apy(self):
        # apy=0 means no data yet; don't recall
        no_data = make_pos("nodata", allocated=50.0, apy=0.0)
        assert underperforming_strategies([no_data]) == []

    def test_exact_threshold_is_not_underperforming(self):
        at_threshold = make_pos("ok", allocated=50.0, apy=RECALL_APY_THRESHOLD)
        assert underperforming_strategies([at_threshold]) == []
