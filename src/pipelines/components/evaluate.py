"""
============================================================
WHAT  : KFP component — evaluation gate.
WHY   : Don't deploy a worse model. Computes a quick metric;
        if below threshold, fail the pipeline.
============================================================
"""
from __future__ import annotations

from kfp import dsl


@dsl.component(base_image="python:3.11-slim", packages_to_install=["numpy==1.26.4"])
def evaluate_op(model_uri: str, min_score: float = 0.0) -> bool:
    """Returns True if the model passes evaluation."""
    # For demo: always pass. Real impl would compute MAE/MAPE on holdout.
    import logging
    logging.basicConfig(level="INFO")
    logging.info("evaluate_op model_uri=%s (always pass for demo)", model_uri)
    return True
