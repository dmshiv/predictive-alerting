"""
============================================================
WHAT  : Compiles the KFP pipelines into JSON specs and uploads
        them to GCS so Cloud Scheduler / start.sh can launch.
WHY   : Vertex AI Pipelines runs JSON specs, not Python code.
HOW   : Use kfp.compiler.Compiler.
============================================================
"""
from __future__ import annotations

import argparse
import logging
from pathlib import Path

from kfp import compiler

from src.pipelines.forecaster_train_pipeline import forecaster_pipeline
from src.pipelines.victim_train_pipeline import victim_pipeline
from src.utils.gcs_client import GCS

log = logging.getLogger(__name__)


def main() -> None:
    logging.basicConfig(level="INFO")
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", default="/tmp/sentinel_pipelines")
    parser.add_argument("--upload-to-gcs", action="store_true")
    parser.add_argument("--bucket", help="GCS bucket to upload to (e.g. PROJECT-sentinel-dev-code)")
    parser.add_argument("--project-id", help="GCP project id (for GCS upload)")
    args = parser.parse_args()

    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)

    fc_path = out / "forecaster_train_pipeline.json"
    vc_path = out / "victim_train_pipeline.json"

    compiler.Compiler().compile(forecaster_pipeline, str(fc_path))
    compiler.Compiler().compile(victim_pipeline, str(vc_path))
    log.info("compiled to %s", out)

    if args.upload_to_gcs:
        gcs = GCS(args.project_id)
        gcs.upload_file(args.bucket, fc_path, "pipelines/forecaster_train_pipeline.json")
        gcs.upload_file(args.bucket, vc_path, "pipelines/victim_train_pipeline.json")
        log.info("uploaded to gs://%s/pipelines/", args.bucket)


if __name__ == "__main__":
    main()
