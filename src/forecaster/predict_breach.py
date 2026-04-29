"""
============================================================
WHAT  : Inference: load forecaster, query last 5 minutes of
        telemetry, predict next 2h, emit prediction rows to
        BQ and (optionally) publish a predictive_alert event.
WHY   : This is the per-minute heartbeat of AI #2.
HOW   : Run on a schedule (cron / Cloud Scheduler) or as a
        long-lived loop on a GKE pod.
============================================================
"""
from __future__ import annotations

import argparse
import logging
import os
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import tensorflow as tf

from src.forecaster.data_window import DEFAULT_METRICS, fetch_telemetry
from src.forecaster.slo_evaluator import SLO_THRESHOLDS, evaluate, evaluate_current
from src.utils.bq_client import BQ
from src.utils.config import get_config
from src.utils.gcs_client import GCS
from src.utils.logging_config import setup_logging
from src.utils.pubsub_client import Publisher

log = logging.getLogger(__name__)


def _download_model(cfg, dest: Path) -> tuple[tf.keras.Model, np.ndarray, np.ndarray, list[str]]:
    gcs = GCS(cfg.project_id)
    # Pull .keras model + norm stats
    blobs = gcs.list_prefix(cfg.bucket_models, "forecaster/")
    if not blobs:
        raise RuntimeError("forecaster model not found in GCS — train it first")
    dest.mkdir(parents=True, exist_ok=True)
    for blob in blobs:
        local = dest / blob.replace("forecaster/", "")
        local.parent.mkdir(parents=True, exist_ok=True)
        gcs.download_file(cfg.bucket_models, blob, local)

    model = tf.keras.models.load_model(dest / "model.keras", compile=False)
    stats = np.load(dest / "norm_stats.npz", allow_pickle=True)
    return model, stats["mean"], stats["std"], list(stats["feature_names"])


def main() -> None:
    setup_logging()
    parser = argparse.ArgumentParser()
    parser.add_argument("--lookback", type=int, default=60)
    parser.add_argument("--horizon", type=int, default=120)
    parser.add_argument("--loop", action="store_true", help="run forever every minute")
    args = parser.parse_args()

    cfg = get_config()
    bq = BQ(cfg.project_id)
    pub = Publisher(cfg.project_id)

    # Load model once
    model, mean, std, feature_names = _download_model(cfg, Path("/tmp/forecaster"))
    log.info("forecaster loaded", extra={"features": feature_names})

    # Per-metric cooldown: don't re-fire the same metric more than once
    # every COOLDOWN_SECONDS while the breach is ongoing.
    COOLDOWN_SECONDS = int(os.environ.get("ALERT_COOLDOWN_SECONDS", "600"))
    last_fired: dict[str, float] = {}

    while True:
        try:
            df = fetch_telemetry(hours=max(args.lookback // 60 + 1, 2), metrics=tuple(feature_names))
            if df.empty or len(df) < args.lookback:
                log.warning("not enough data yet", extra={"have": len(df), "need": args.lookback})
            else:
                X = df.iloc[-args.lookback:].values.astype(np.float32)
                Xn = (X[None, ...] - mean) / std
                pred = model.predict(Xn, verbose=0)
                mean_fc = pred["mean"][0] * std[0] + mean[0]   # (horizon, F)
                band_fc = pred["band"][0] * std[0]              # (horizon, F)

                # 1. Persist predictions to BigQuery
                now = datetime.now(timezone.utc)
                rows = []
                for h in range(mean_fc.shape[0]):
                    for f_i, fname in enumerate(feature_names):
                        rows.append({
                            "predicted_at": now.isoformat(),
                            "horizon_minutes": h + 1,
                            "metric_name": fname,
                            "predicted_value": float(mean_fc[h, f_i]),
                            "lower_bound": float(mean_fc[h, f_i] - band_fc[h, f_i]),
                            "upper_bound": float(mean_fc[h, f_i] + band_fc[h, f_i]),
                            "model_version": "v1",
                        })
                bq.insert_rows(cfg.bq_predictions_table, rows)
                log.info("predictions written", extra={"event": "forecast_run", "n_rows": len(rows)})

                # 2. Evaluate SLO breach risk
                # 2a. Predictive: forecast crosses threshold within horizon
                forecast_breaches = evaluate(mean_fc, band_fc, feature_names)
                # 2b. Reactive: most recent observed value already crosses threshold
                last_row = df.iloc[-1]
                current_values = {f: float(last_row[f]) for f in feature_names if f in df.columns}
                current_breaches = evaluate_current(current_values)

                # De-duplicate: if both fire for the same metric, prefer the
                # predictive one (it has lead-time info).
                breaches_by_metric: dict[str, dict] = {}
                for b in current_breaches:
                    breaches_by_metric[b["metric_name"]] = b
                for b in forecast_breaches:
                    breaches_by_metric[b["metric_name"]] = b
                breaches = list(breaches_by_metric.values())

                for breach in breaches:
                    metric = breach["metric_name"]
                    # Cooldown: skip if the same metric fired recently
                    elapsed = time.time() - last_fired.get(metric, 0)
                    if elapsed < COOLDOWN_SECONDS:
                        log.info(
                            "breach detected but in cooldown",
                            extra={"event": "alert_cooldown", "metric": metric,
                                   "seconds_remaining": int(COOLDOWN_SECONDS - elapsed)},
                        )
                        continue

                    incident_id = str(uuid.uuid4())
                    payload = {
                        "incident_id": incident_id,
                        "fired_at": now.isoformat(),
                        "predicted_breach_at": breach["predicted_breach_at"],
                        "endpoint_id": cfg.endpoint_victim,
                        "metric_name": metric,
                        "severity": breach["severity"],
                        "feature_fingerprint": breach.get("fingerprint", {}),
                    }
                    pub.publish_json(cfg.topic_incidents, payload)
                    last_fired[metric] = time.time()
                    log.warning(
                        "predictive alert fired",
                        extra={"event": "predictive_alert",
                               "source": breach.get("source", "forecast"), **payload},
                    )

        except Exception:
            log.exception("forecast iteration failed; will retry")

        if not args.loop:
            return
        time.sleep(60)


if __name__ == "__main__":
    main()
