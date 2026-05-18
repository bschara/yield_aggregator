"""FastAPI policy server — exposes POST /decide for the TypeScript main loop."""

from fastapi import FastAPI
from .risk_model import VaultState
from .rebalance_policy import Action, decide

app = FastAPI(title="Yield Aggregator Policy Server")


@app.post("/decide", response_model=Action)
def decide_action(state: VaultState) -> Action:
    """Given current vault state, return the next action to execute."""
    return decide(state)


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}
