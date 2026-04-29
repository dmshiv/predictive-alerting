"""
============================================================
WHAT  : KFP component — preprocess BigQuery telemetry into
        a numpy archive on GCS for the forecaster trainer.
WHY   : Decouples I/O from training so each stage is testable.
HOW   : Light wrapper that calls fetch_telemetry and saves.
============================================================
"""
from __future__ import annotations

from kfp import dsl


@dsl.component(
    base_image="python:3.11-slim",
    packages_to_install=[
        "google-cloud-bigquery==3.27.0",
        "google-cloud-storage==2.18.0",
        "pandas==2.2.3",
        "pyarrow==17.0.0",
        "tenacity==9.0.0",
    ],
)
def preprocess_op(project_id: str, region: str, env_name: str, hours: int, output_uri: str) -> str:
    """Fetch last N hours of telemetry from BQ, save parquet to GCS, return URI."""
    import logging
    from datetime import datetime
    from google.cloud import bigquery, storage
    import pandas as pd

    logging.basicConfig(level="INFO")
    log = logging.getLogger("preprocess")

    dataset = f"sentinel_{env_name}_features".replace("-", "_")
    table = f"{project_id}.{dataset}.telemetry_raw"
    sql = f"""
      SELECT
        TIMESTAMP_TRUNC(event_time, MINUTE) AS minute,
        metric_name,
        AVG(metric_value) AS value
      FROM `{table}`
      WHERE event_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL {hours} HOUR)
      GROUP BY minute, metric_name
      ORDER BY minute
    """
    bq = bigquery.Client(project=project_id)
    df = bq.query(sql).to_dataframe()
    log.info("rows fetched: %d", len(df))

    out_path = f"/tmp/telemetry_{datetime.utcnow().strftime('%Y%m%d_%H%M')}.parquet"
    df.to_parquet(out_path)

    # Upload to GCS
    if output_uri.startswith("gs://"):
        bucket_name, _, key = output_uri.replace("gs://", "").partition("/")
        client = storage.Client(project=project_id)
        blob = client.bucket(bucket_name).blob(key + "/telemetry.parquet")
        blob.upload_from_filename(out_path)
        return f"gs://{bucket_name}/{key}/telemetry.parquet"
    return out_path
