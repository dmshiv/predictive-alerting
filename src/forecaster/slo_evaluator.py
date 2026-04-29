"""
============================================================
WHAT  : Decides "will SLO breach in the next 2h?" given the
        forecast bands.
WHY   : Separates the math (forecasting) from the policy
        (what counts as a breach).
HOW   : Per-metric thresholds; if upper-bound forecast crosses
        threshold within `min_lead_time_minutes`, fire.
============================================================
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

import numpy as np

log = logging.getLogger(__name__)

# SLO thresholds: (metric_name, comparison_op, threshold)
# Tweak these to make the demo more or less sensitive.
SLO_THRESHOLDS: dict[str, tuple[str, float, str]] = {
    # metric            : (op, threshold, severity)
    "latency_ms":          ("gt", 300.0, "high"),
    "error_rate":          ("gt", 0.02,  "high"),
    "image_embedding_norm":("gt", 1.20,  "medium"),  # drift signal
    "review_token_count":  ("lt", 10.0,  "low"),
}


def evaluate(
    mean_forecast: np.ndarray,    # (horizon, F)
    band_forecast: np.ndarray,    # (horizon, F)
    feature_names: list[str],
    min_lead_time_minutes: int = 1,
) -> list[dict]:
    """Return a list of breach descriptors (empty if none)."""
    breaches: list[dict] = []
    horizon, F = mean_forecast.shape
    now = datetime.now(timezone.utc)

    for f_i, fname in enumerate(feature_names):
        spec = SLO_THRESHOLDS.get(fname)
        if spec is None:
            continue
        op, thresh, severity = spec
        upper = mean_forecast[:, f_i] + band_forecast[:, f_i]
        lower = mean_forecast[:, f_i] - band_forecast[:, f_i]

        if op == "gt":
            crossing = np.where(upper >= thresh)[0]
        elif op == "lt":
            crossing = np.where(lower <= thresh)[0]
        else:
            continue

        if len(crossing) == 0:
            continue

        first_minute = int(crossing[0]) + 1
        if first_minute < min_lead_time_minutes:
            # Too late — current state already broken; let infra alerts handle it
            continue

        breach_time = now + timedelta(minutes=first_minute)
        breaches.append({
            "metric_name": fname,
            "predicted_breach_at": breach_time.isoformat(),
            "lead_time_minutes": first_minute,
            "severity": severity,
            "operator": op,
            "threshold": thresh,
            "predicted_peak": float(upper.max() if op == "gt" else lower.min()),
        })
        log.info("breach forecasted", extra={
            "event": "breach_forecast",
            "metric": fname,
            "lead_time_minutes": first_minute,
            "severity": severity,
        })

    return breaches


def evaluate_current(
    current_values: dict[str, float],
) -> list[dict]:
    """Reactive evaluator: fires when the most recent observed value
    already crosses the SLO threshold. Complements the predictive
    evaluator above for cases where the LSTM cannot extrapolate
    out-of-distribution inputs (e.g. sudden hardware degradation).
    """
    breaches: list[dict] = []
    now = datetime.now(timezone.utc)
    for fname, value in current_values.items():
        spec = SLO_THRESHOLDS.get(fname)
        if spec is None:
            continue
        op, thresh, severity = spec
        crossed = (op == "gt" and value > thresh) or (op == "lt" and value < thresh)
        if not crossed:
            continue
        breaches.append({
            "metric_name": fname,
            "predicted_breach_at": now.isoformat(),
            "lead_time_minutes": 0,
            "severity": severity,
            "operator": op,
            "threshold": thresh,
            "predicted_peak": float(value),
            "source": "reactive",
        })
        log.warning("current state breach", extra={
            "event": "current_breach",
            "metric": fname,
            "value": value,
            "threshold": thresh,
            "severity": severity,
        })
    return breaches
