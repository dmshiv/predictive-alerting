"""SLO breach detection unit tests — the heart of the alerting logic."""
import numpy as np

from src.forecaster.slo_evaluator import evaluate, SLO_THRESHOLDS


def test_no_breach_when_below_threshold():
    horizon, F = 120, 1
    feature_names = ["latency_ms"]
    mean = np.full((horizon, F), 100.0)   # well below 300
    band = np.full((horizon, F), 5.0)
    breaches = evaluate(mean, band, feature_names)
    assert breaches == []


def test_breach_when_upper_crosses_threshold():
    """Mean ramps up over time so breach is forecast 30 min out (sufficient lead)."""
    horizon, F = 120, 1
    feature_names = ["latency_ms"]
    # Healthy now (100), climbing to 400 by horizon end -> crosses 300 around minute ~67
    mean = np.linspace(100.0, 400.0, horizon).reshape(horizon, F)
    band = np.full((horizon, F), 10.0)
    breaches = evaluate(mean, band, feature_names)
    assert len(breaches) == 1
    assert breaches[0]["metric_name"] == "latency_ms"
    assert breaches[0]["severity"] == "high"
    assert breaches[0]["lead_time_minutes"] >= 5


def test_breach_too_soon_is_skipped():
    """If breach forecast lead-time < min_lead_time_minutes, skip."""
    horizon, F = 120, 1
    feature_names = ["latency_ms"]
    mean = np.full((horizon, F), 1000.0)   # already breaching now
    band = np.full((horizon, F), 50.0)
    breaches = evaluate(mean, band, feature_names, min_lead_time_minutes=10)
    # First crossing at minute 1 -- skipped (we want lead-time alerts only)
    assert breaches == []


def test_drift_lt_op_triggers():
    """`lt` op: review_token_count drops below 10 over time."""
    horizon, F = 120, 1
    feature_names = ["review_token_count"]    # op = lt, threshold = 10
    # Starts healthy at 25, drops to 5 by end -> crosses 10 around minute ~75
    mean = np.linspace(25.0, 5.0, horizon).reshape(horizon, F)
    band = np.full((horizon, F), 1.0)
    breaches = evaluate(mean, band, feature_names)
    assert len(breaches) == 1
    assert breaches[0]["operator"] == "lt"
