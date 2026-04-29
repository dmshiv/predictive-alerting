"""
============================================================
Pytest fixtures. Set fake env vars so `get_config()` works
without a real GCP project.
============================================================
"""
import os
import pytest


@pytest.fixture(autouse=True)
def _stub_env(monkeypatch):
    monkeypatch.setenv("GCP_PROJECT_ID", "test-project")
    monkeypatch.setenv("GCP_REGION", "us-central1")
    monkeypatch.setenv("GCP_ZONE", "us-central1-a")
    monkeypatch.setenv("ENV_NAME", "test")
    yield
