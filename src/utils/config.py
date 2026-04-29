"""
============================================================
WHAT  : Central config loader. Reads .env / OS env, derives
        names of every shared resource (buckets, datasets,
        topics, endpoints) so we never hard-code anywhere.
WHY   : One file controls every name. Change ENV_NAME and
        the whole project picks up the new resource names.
HOW   : Env vars are populated by start.sh from .env.
LAYMAN: Like a sticky note that says "the project is named
        X, the bucket is named Y, the topic is Z" — every
        Python file reads it once at import time.
============================================================
"""
from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache


@dataclass(frozen=True)
class Config:
    """Runtime configuration for any Sentinel-Forecast workload."""

    project_id: str
    region: str
    zone: str
    env_name: str

    # Derived names (must match the Terraform `name_prefix` convention)
    @property
    def name_prefix(self) -> str:
        return f"sentinel-{self.env_name}"

    @property
    def bq_dataset_features(self) -> str:
        return f"sentinel_{self.env_name}_features".replace("-", "_")

    @property
    def bq_dataset_incidents(self) -> str:
        return f"sentinel_{self.env_name}_incidents".replace("-", "_")

    @property
    def bq_telemetry_table(self) -> str:
        return f"{self.project_id}.{self.bq_dataset_features}.telemetry_raw"

    @property
    def bq_predictions_table(self) -> str:
        return f"{self.project_id}.{self.bq_dataset_features}.predictions"

    @property
    def bq_incidents_table(self) -> str:
        return f"{self.project_id}.{self.bq_dataset_incidents}.incidents"

    @property
    def bucket_models(self) -> str:
        return f"{self.project_id}-{self.name_prefix}-models"

    @property
    def bucket_processed(self) -> str:
        return f"{self.project_id}-{self.name_prefix}-processed"

    @property
    def bucket_raw_data(self) -> str:
        return f"{self.project_id}-{self.name_prefix}-raw-data"

    @property
    def bucket_tb_logs(self) -> str:
        return f"{self.project_id}-{self.name_prefix}-tb-logs"

    @property
    def bucket_code(self) -> str:
        return f"{self.project_id}-{self.name_prefix}-code"

    @property
    def topic_raw_traffic(self) -> str:
        return f"{self.name_prefix}-raw-traffic"

    @property
    def topic_telemetry(self) -> str:
        return f"{self.name_prefix}-telemetry"

    @property
    def topic_incidents(self) -> str:
        return f"{self.name_prefix}-incidents"

    @property
    def endpoint_victim(self) -> str:
        return f"projects/{self.project_id}/locations/{self.region}/endpoints/victim-recommender"

    @property
    def endpoint_forecaster(self) -> str:
        return f"projects/{self.project_id}/locations/{self.region}/endpoints/forecaster"

    @property
    def secret_gemini_key(self) -> str:
        return f"{self.name_prefix}-gemini-api-key"

    @property
    def secret_slack_webhook(self) -> str:
        return f"{self.name_prefix}-slack-webhook"


def _project_id_from_metadata() -> str | None:
    """Last-resort: ask the GCE metadata server (works on Vertex AI, GKE, GCE, Cloud Run)."""
    try:
        import urllib.request
        req = urllib.request.Request(
            "http://metadata.google.internal/computeMetadata/v1/project/project-id",
            headers={"Metadata-Flavor": "Google"},
        )
        with urllib.request.urlopen(req, timeout=1.0) as resp:
            return resp.read().decode("utf-8").strip() or None
    except Exception:
        return None


def _region_from_metadata() -> str | None:
    try:
        import urllib.request
        req = urllib.request.Request(
            "http://metadata.google.internal/computeMetadata/v1/instance/zone",
            headers={"Metadata-Flavor": "Google"},
        )
        with urllib.request.urlopen(req, timeout=1.0) as resp:
            zone = resp.read().decode("utf-8").strip().rsplit("/", 1)[-1]
            return zone.rsplit("-", 1)[0] if zone else None
    except Exception:
        return None


@lru_cache(maxsize=1)
def get_config() -> Config:
    """
    Resolve project_id from (in order):
      1. GCP_PROJECT_ID env var          (set by start.sh / .env)
      2. GOOGLE_CLOUD_PROJECT env var    (set by Google client libs)
      3. GCE metadata server             (works on Vertex / GKE / Cloud Run / GCE)
    Vertex AI new-model-version uploads do NOT propagate --container-env-vars,
    so the metadata fallback is the only reliable source there.
    """
    project_id = (
        os.environ.get("GCP_PROJECT_ID")
        or os.environ.get("GOOGLE_CLOUD_PROJECT")
        or _project_id_from_metadata()
    )
    if not project_id:
        raise RuntimeError(
            "Could not resolve project_id from GCP_PROJECT_ID, GOOGLE_CLOUD_PROJECT, "
            "or the GCE metadata server. Set GCP_PROJECT_ID explicitly."
        )
    region = (
        os.environ.get("GCP_REGION")
        or _region_from_metadata()
        or "us-central1"
    )
    return Config(
        project_id=project_id,
        region=region,
        zone=os.environ.get("GCP_ZONE", f"{region}-a"),
        env_name=os.environ.get("ENV_NAME", "dev"),
    )
