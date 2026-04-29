"""
============================================================
WHAT  : KFP pipeline that retrains the victim recommender (AI #1).
        Triggered nightly by Cloud Scheduler.
HOW   : train_victim -> evaluate -> register_model
============================================================
"""
from __future__ import annotations

from kfp import dsl

from src.pipelines.components.evaluate import evaluate_op
from src.pipelines.components.register_model import register_model_op
from src.pipelines.components.train_victim import train_victim_op


@dsl.pipeline(name="sentinel-victim-train", description="Nightly retrain of the victim recommender")
def victim_pipeline(
    project_id: str,
    region: str,
    env_name: str,
    bucket_models: str,
    serving_container: str,
):
    tr = train_victim_op(
        project_id=project_id,
        env_name=env_name,
        output_uri=f"gs://{bucket_models}/victim",
        n_products=200,
    )
    ev = evaluate_op(model_uri=tr.output)
    with dsl.If(ev.output == True):  # noqa: E712
        register_model_op(
            project_id=project_id,
            region=region,
            model_uri=f"gs://{bucket_models}/victim",
            display_name=f"sentinel-{env_name}-victim",
            serving_container=serving_container,
            endpoint_name=f"sentinel-{env_name}-victim-recommender",
        )
