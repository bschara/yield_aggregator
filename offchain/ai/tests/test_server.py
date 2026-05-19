"""HTTP layer tests for server.py — uses FastAPI TestClient."""

import pytest
from fastapi.testclient import TestClient
from ..server import app
from ..risk_model import VaultState, StrategyPosition


client = TestClient(app)


def minimal_vault_state(**overrides) -> dict:
    base = {
        "tvl": 100.0,
        "idleAssets": 50.0,
        "deployedAssets": 50.0,
        "utilization": 0.5,
        "strategies": [
            {
                "strategyId": "0",
                "capitalAllocated": 50.0,
                "maxExposure": 100.0,
                "apy": 0.10,
                "riskScore": 0.2,
                "lastHarvestTs": 0,
            }
        ],
        "snapshotTs": 1_000_000,
        "pendingBridges": [],
    }
    base.update(overrides)
    return base


# ── GET /health ───────────────────────────────────────────────────────────────

class TestHealthEndpoint:
    def test_returns_200(self):
        r = client.get("/health")
        assert r.status_code == 200

    def test_body_is_ok(self):
        r = client.get("/health")
        assert r.json() == {"status": "ok"}


# ── POST /decide ──────────────────────────────────────────────────────────────

class TestDecideEndpoint:
    def test_returns_200_with_valid_state(self):
        r = client.post("/decide", json=minimal_vault_state())
        assert r.status_code == 200

    def test_response_has_action_schema(self):
        r = client.post("/decide", json=minimal_vault_state())
        body = r.json()
        assert "type" in body
        assert body["type"] in {"deploy", "recall", "harvest", "none"}
        assert "reason" in body

    def test_optional_fields_present_or_null(self):
        r = client.post("/decide", json=minimal_vault_state())
        body = r.json()
        # strategyId and amountOctas may be absent or null
        assert "strategyId" in body or body.get("strategyId") is None

    def test_overexposed_strategy_triggers_recall(self):
        state = minimal_vault_state(
            strategies=[
                {
                    "strategyId": "0",
                    "capitalAllocated": 150.0,
                    "maxExposure": 100.0,
                    "apy": 0.10,
                    "riskScore": 0.2,
                    "lastHarvestTs": 0,
                }
            ]
        )
        r = client.post("/decide", json=state)
        assert r.status_code == 200
        assert r.json()["type"] == "recall"
        assert r.json()["strategyId"] == "0"

    def test_invalid_body_returns_422(self):
        r = client.post("/decide", json={"invalid": "payload"})
        assert r.status_code == 422

    def test_missing_required_field_returns_422(self):
        # Remove 'utilization' which is required by VaultState
        state = minimal_vault_state()
        del state["utilization"]
        r = client.post("/decide", json=state)
        assert r.status_code == 422
