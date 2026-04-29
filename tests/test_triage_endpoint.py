"""Smoke test the FastAPI triage app: /healthz and /alert routing.

We use TestClient against the app, mocking out the heavy externals
(BigQuery, Pub/Sub, Slack, Gemini)."""
import json
from unittest import mock

import pytest


@pytest.fixture
def client(monkeypatch):
    # Patch heavy externals BEFORE importing the app
    monkeypatch.setattr("src.triage.gemini_triage.GeminiTriage._configure", lambda self: False)
    monkeypatch.setattr("src.triage.incident_writer.IncidentWriter.write", lambda *a, **kw: None)
    monkeypatch.setattr("src.triage.slack_notify.SlackNotifier._webhook", lambda self: "")
    monkeypatch.setattr("src.triage.email_notify.EmailNotifier.post", lambda *a, **kw: True)

    from fastapi.testclient import TestClient
    from src.triage import main as triage_main
    return TestClient(triage_main.app)


def test_healthz(client):
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json()["ok"] is True


def test_alert_direct_invocation(client):
    incident = {
        "incident_id": "test-1",
        "fired_at": "2026-01-01T00:00:00Z",
        "predicted_breach_at": "2026-01-01T00:10:00Z",
        "metric_name": "latency_ms",
        "severity": "high",
        "lead_time_minutes": 10,
        "operator": "gt",
        "threshold": 300,
        "predicted_peak": 450,
        "feature_fingerprint": {},
    }
    r = client.post("/alert", json=incident)
    assert r.status_code == 200
    body = r.json()
    assert body["ok"] is True
    assert body["incident_id"] == "test-1"
    assert body["runbook_id"] == "scale_pods"
