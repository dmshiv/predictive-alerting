"""
============================================================
WHAT  : KFP pipeline that retrains the forecaster (AI #2).
        Triggered every 6h by Cloud Scheduler (10-pipelines/scheduler.tf).
WHY   : Forecasts get stale; retrain on the latest 7 days of telemetry.
HOW   : preprocess -> train_forecaster -> evaluate -> register_model
============================================================
"""
from __future__ import annotations

from kfp import dsl

from src.pipelines.components.evaluate import evaluate_op
from src.pipelines.components.preprocess import preprocess_op
from src.pipelines.components.register_model import register_model_op
from src.pipelines.components.train_forecaster import train_forecaster_op


@dsl.pipeline(name="sentinel-forecaster-train", description="Retrain forecaster on recent telemetry")
def forecaster_pipeline(
    project_id: str,
    region: str,
    env_name: str,
    bucket_processed: str,
    bucket_models: str,
    serving_container: str,
):
    pp = preprocess_op(
        project_id=project_id,
        region=region,
        env_name=env_name,
        hours=168,
        output_uri=f"gs://{bucket_processed}/forecaster",
    )
    tr = train_forecaster_op(
        project_id=project_id,
        region=region,
        env_name=env_name,
        input_parquet_uri=pp.output,
        output_model_uri=f"gs://{bucket_models}/forecaster",
        epochs=5,
    )
    ev = evaluate_op(model_uri=tr.output)
    with dsl.If(ev.output == True):  # noqa: E712
        register_model_op(
            project_id=project_id,
            region=region,
            model_uri=f"gs://{bucket_models}/forecaster/saved_model",
            display_name=f"sentinel-{env_name}-forecaster",
            serving_container=serving_container,
            endpoint_name=f"sentinel-{env_name}-forecaster",
        )
