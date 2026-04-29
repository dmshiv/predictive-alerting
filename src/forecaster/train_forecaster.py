"""
============================================================
WHAT  : Trains the TensorFlow forecaster on BigQuery telemetry.
WHY   : So AI #2 learns to predict AI #1's vitals.
HOW   : 1. Pull last 7d of telemetry from BQ
        2. Sliding-window into (X, Y) pairs
        3. Fit encoder-decoder LSTM
        4. Save SavedModel format to GCS
        5. Log scalars to TensorBoard
============================================================
"""
from __future__ import annotations

import argparse
import logging
import os
from datetime import datetime
from pathlib import Path

import numpy as np
import tensorflow as tf

from src.forecaster.data_window import DEFAULT_METRICS, WindowConfig, fetch_telemetry, make_windows
from src.forecaster.temporal_forecaster import build_forecaster, mean_mse, band_magnitude_loss
from src.utils.config import get_config
from src.utils.gcs_client import GCS
from src.utils.logging_config import setup_logging

log = logging.getLogger(__name__)


def main() -> None:
    setup_logging()
    parser = argparse.ArgumentParser()
    parser.add_argument("--lookback", type=int, default=60)
    parser.add_argument("--horizon", type=int, default=120)
    parser.add_argument("--hours", type=int, default=168)
    parser.add_argument("--epochs", type=int, default=10)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--out-dir", type=str, default="/tmp/sentinel_forecaster")
    parser.add_argument("--upload-to-gcs", action="store_true")
    args = parser.parse_args()

    cfg = get_config()

    # 1. Fetch
    df = fetch_telemetry(hours=args.hours, metrics=DEFAULT_METRICS)
    if df.empty:
        log.warning("no telemetry; generating synthetic for cold-start training")
        # Synthetic stand-in so training works on day 1
        T = 60 * 24 * 3
        np.random.seed(0)
        synthetic = np.column_stack([
            120 + 20 * np.sin(np.arange(T) * 2 * np.pi / 60) + np.random.randn(T) * 5,   # latency
            1.0 + 0.05 * np.random.randn(T),                                              # image_norm
            20 + np.random.randn(T) * 3,                                                  # tokens
            (np.random.rand(T) < 0.01).astype(np.float32),                                # error rate
        ])
        import pandas as pd
        df = pd.DataFrame(synthetic, columns=list(DEFAULT_METRICS))

    # 2. Window
    win_cfg = WindowConfig(lookback_minutes=args.lookback, horizon_minutes=args.horizon)
    X, Y = make_windows(df, win_cfg)
    if len(X) == 0:
        raise RuntimeError("not enough data for training")

    # Normalize per-feature
    mean = X.mean(axis=(0, 1), keepdims=True)
    std = X.std(axis=(0, 1), keepdims=True) + 1e-6
    Xn = (X - mean) / std
    Yn = (Y - mean) / std
    log.info("windows", extra={"X_shape": str(Xn.shape), "Y_shape": str(Yn.shape)})

    # 3. Train
    n_features = Xn.shape[-1]
    model = build_forecaster(n_features=n_features, lookback=args.lookback, horizon=args.horizon)
    model.compile(
        optimizer="adam",
        loss={"mean": mean_mse, "band": band_magnitude_loss},
        loss_weights={"mean": 1.0, "band": 0.3},
    )

    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)

    tb_log_dir = str(out / "tb_logs" / datetime.utcnow().strftime("%Y%m%d-%H%M%S"))
    cbs = [
        tf.keras.callbacks.TensorBoard(log_dir=tb_log_dir, histogram_freq=0),
        tf.keras.callbacks.EarlyStopping(patience=3, restore_best_weights=True, monitor="loss"),
    ]

    # Two-output trick: tf wants y in same structure as the model output dict
    y_dict = {"mean": Yn, "band": Yn}
    model.fit(Xn, y_dict, epochs=args.epochs, batch_size=args.batch_size, callbacks=cbs)

    # 4. Save (Keras 3 native format)
    saved_path = out / "model.keras"
    model.save(saved_path)
    np.savez_compressed(out / "norm_stats.npz", mean=mean, std=std,
                        feature_names=np.array(list(df.columns)))
    log.info("saved forecaster", extra={"path": str(saved_path)})

    if args.upload_to_gcs:
        gcs = GCS(cfg.project_id)
        gcs.upload_file(cfg.bucket_models, saved_path, "forecaster/model.keras")
        gcs.upload_file(cfg.bucket_models, out / "norm_stats.npz", "forecaster/norm_stats.npz")
        log.info("uploaded forecaster to GCS")


if __name__ == "__main__":
    main()
