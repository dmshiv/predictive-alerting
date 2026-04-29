"""Runbook recommender returns expected runbooks for known fingerprints."""
import pytest

from src.runbook_recommender.recommender import RunbookRecommender, load_runbook_library


@pytest.fixture(scope="module")
def recommender():
    library = load_runbook_library("src/runbook_recommender/runbooks")
    return RunbookRecommender(library)


def test_library_loads(recommender):
    assert len(recommender.library) >= 4


def test_latency_recommends_scale_pods(recommender):
    rec = recommender.recommend({"metric_name": "latency_ms", "severity": "high"})
    assert any(rb_id == "scale_pods" for rb_id, _ in rec)


def test_drift_recommends_rollback_or_refresh(recommender):
    rec = recommender.recommend({"metric_name": "image_embedding_norm", "severity": "medium"})
    rb_ids = [rb for rb, _ in rec]
    assert "rollback_model" in rb_ids or "refresh_features" in rb_ids


def test_unknown_falls_back(recommender):
    rec = recommender.recommend({"metric_name": "nonsense", "severity": "low"})
    # Either empty (no triggers fire) -> fallback first or specific match
    assert len(rec) >= 1
