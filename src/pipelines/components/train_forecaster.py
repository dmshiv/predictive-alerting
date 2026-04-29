"""
============================================================
WHAT  : KFP component — trains the forecaster.
WHY   : Stage in the forecaster_train_pipeline DAG.
HOW   : Calls src/forecaster/train_forecaster.py main().
============================================================
"""
from __future__ import annotations

from kfp import dsl


@dsl.component(
    base_image="python:3.11-slim",
    packages_to_install=[
        "tensorflow==2.17.0",
        "google-cloud-storage==2.18.0",
        "google-cloud-bigquery==3.27.0",
        "pandas==2.2.3",
        "pyarrow==17.0.0",
    ],
)
def train_forecaster_op(
    project_id: str,
    region: str,
    env_name: str,
    input_parquet_uri: str,
    output_model_uri: str,
    epochs: int = 5,
    lookback: int = 60,
    horizon: int = 120,
) -> str:
    """Trains the forecaster, saves to GCS, returns the GCS URI."""
    import logging
    import numpy as np
    import pandas as pd
    import tensorflow as tf
    from tensorflow import keras
    from tensorflow.keras import layers
    from google.cloud import storage

    logging.basicConfig(level="INFO")
    log = logging.getLogger("train_forecaster_op")

    # Load parquet from GCS
    if input_parquet_uri.startswith("gs://"):
        bucket_name, _, key = input_parquet_uri.replace("gs://", "").partition("/")
        client = storage.Client(project=project_id)
        client.bucket(bucket_name).blob(key).download_to_filename("/tmp/telemetry.parquet")
        df = pd.read_parquet("/tmp/telemetry.parquet")
    else:
        df = pd.read_parquet(input_parquet_uri)

    pivot = df.pivot(index="minute", columns="metric_name", values="value").ffill().fillna(0)
    arr = pivot.values.astype(np.float32)

    # Sliding windows
    Xs, Ys = [], []
    for s in range(0, max(0, len(arr) - lookback - horizon), 5):
        Xs.append(arr[s:s+lookback])
        Ys.append(arr[s+lookback:s+lookback+horizon])
    if not Xs:
        log.warning("not enough data; bailing")
        return ""
    X, Y = np.stack(Xs), np.stack(Ys)
    mean = X.mean((0,1), keepdims=True); std = X.std((0,1), keepdims=True) + 1e-6
    Xn = (X - mean) / std; Yn = (Y - mean) / std

    F = X.shape[-1]
    inp = keras.Input(shape=(lookback, F))
    h = layers.LSTM(64)(inp)
    out_mean = layers.Reshape((horizon, F))(layers.Dense(horizon * F)(h))
    band = layers.Reshape((horizon, F))(layers.Dense(horizon * F, activation="softplus")(layers.LSTM(64)(inp)))
    model = keras.Model(inp, {"mean": out_mean, "band": band})
    model.compile(optimizer="adam", loss="mse")
    model.fit(Xn, {"mean": Yn, "band": Yn}, epochs=epochs, batch_size=32, verbose=2)

    saved = "/tmp/saved_model"
    model.save(saved)
    np.savez_compressed("/tmp/norm_stats.npz", mean=mean, std=std,
                        feature_names=np.array(list(pivot.columns)))

    if output_model_uri.startswith("gs://"):
        bucket_name, _, key = output_model_uri.replace("gs://", "").partition("/")
        client = storage.Client(project=project_id)
        # Walk saved_model dir
        from pathlib import Path as _P
        for f in _P(saved).rglob("*"):
            if f.is_file():
                rel = f.relative_to(saved)
                client.bucket(bucket_name).blob(f"{key}/saved_model/{rel}").upload_from_filename(str(f))
        client.bucket(bucket_name).blob(f"{key}/norm_stats.npz").upload_from_filename("/tmp/norm_stats.npz")
        return output_model_uri
    return saved
