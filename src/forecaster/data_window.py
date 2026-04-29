"""
============================================================
WHAT  : Builds sliding-window training/inference features
        from BigQuery telemetry.
WHY   : Time-series models need (input_window, target_window)
        pairs; this module produces them.
HOW   : Query last N hours -> pivot to per-metric series ->
        slide a window of `lookback` minutes producing
        (input, target) pairs.
============================================================
"""
from __future__ import annotations

import logging
from dataclasses import dataclass

import numpy as np
import pandas as pd

from src.utils.bq_client import BQ
from src.utils.config import get_config

log = logging.getLogger(__name__)

DEFAULT_METRICS = (
    "latency_ms",
    "image_embedding_norm",
    "review_token_count",
    "error_rate",
)


@dataclass
class WindowConfig:
    lookback_minutes: int = 60
    horizon_minutes: int = 120
    stride_minutes: int = 5


def fetch_telemetry(hours: int = 168, metrics: tuple[str, ...] = DEFAULT_METRICS) -> pd.DataFrame:
    """Pull last N hours of telemetry and pivot to per-metric columns."""
    cfg = get_config()
    bq = BQ(cfg.project_id)
    metric_list = ",".join(f"'{m}'" for m in metrics)
    sql = f"""
      SELECT
        TIMESTAMP_TRUNC(event_time, MINUTE) AS minute,
        metric_name,
        AVG(metric_value) AS value
      FROM `{cfg.bq_telemetry_table}`
      WHERE event_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL {hours} HOUR)
        AND metric_name IN ({metric_list})
      GROUP BY minute, metric_name
      ORDER BY minute
    """
    df = bq.query_df(sql)
    if df.empty:
        log.warning("no telemetry yet; returning empty df")
        return df
    pivot = df.pivot(index="minute", columns="metric_name", values="value").ffill().fillna(0)
    return pivot


def make_windows(
    df: pd.DataFrame,
    cfg: WindowConfig | None = None,
) -> tuple[np.ndarray, np.ndarray]:
    """Returns (X, Y) where:
      X is (N, lookback, n_features)
      Y is (N, horizon,  n_features)"""
    cfg = cfg or WindowConfig()
    if df.empty:
        return np.zeros((0,)), np.zeros((0,))

    arr = df.values.astype(np.float32)             # (T, F)
    L, H, S = cfg.lookback_minutes, cfg.horizon_minutes, cfg.stride_minutes
    if len(arr) < L + H:
        return np.zeros((0,)), np.zeros((0,))

    Xs, Ys = [], []
    for start in range(0, len(arr) - L - H, S):
        Xs.append(arr[start : start + L])
        Ys.append(arr[start + L : start + L + H])
    return np.stack(Xs), np.stack(Ys)
