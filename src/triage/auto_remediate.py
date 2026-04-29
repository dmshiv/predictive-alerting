"""
============================================================
WHAT  : Auto-remediation actions triggered by triage.
WHY   : If we can roll back / scale automatically, the SLO
        truly never breaks (the holy grail).
HOW   : Each action is a small, idempotent function.
        ACTION_REGISTRY maps runbook IDs to functions.
NOTE  : We default to DRY-RUN mode unless AUTO_REMEDIATE=true
        is set as an env var. This keeps the demo safe.
============================================================
"""
from __future__ import annotations

import logging
import os

log = logging.getLogger(__name__)


def _dry_run() -> bool:
    return os.environ.get("AUTO_REMEDIATE", "false").lower() != "true"


def rollback_model(incident: dict) -> dict:
    """Switch traffic on the victim endpoint to the previous deployed model."""
    if _dry_run():
        log.info("DRY-RUN rollback_model", extra={"incident": incident.get("incident_id")})
        return {"action": "rollback_model", "status": "dry_run"}

    try:
        from google.cloud import aiplatform
        from src.utils.config import get_config
        cfg = get_config()
        aiplatform.init(project=cfg.project_id, location=cfg.region)
        endpoint = aiplatform.Endpoint(cfg.endpoint_victim)
        deployed = endpoint.list_models()
        if len(deployed) < 2:
            return {"action": "rollback_model", "status": "skipped", "reason": "only one model deployed"}
        # Take the next-most-recent
        prev = deployed[1]
        endpoint.update_traffic_split({prev.id: 100})
        return {"action": "rollback_model", "status": "applied", "to_model_id": prev.id}
    except Exception as e:
        log.exception("rollback_model failed")
        return {"action": "rollback_model", "status": "error", "error": str(e)}


def scale_pods(incident: dict) -> dict:
    """Increase HPA min replicas on the GKE detector deployment."""
    if _dry_run():
        log.info("DRY-RUN scale_pods", extra={"incident": incident.get("incident_id")})
        return {"action": "scale_pods", "status": "dry_run"}

    # Real implementation would shell out to kubectl or use the kubernetes client.
    # Skipped here to keep the Cloud Run container small.
    return {"action": "scale_pods", "status": "deferred", "note": "use kubectl in pipeline"}


def refresh_features(incident: dict) -> dict:
    """Trigger a fresh victim-retrain pipeline run."""
    if _dry_run():
        log.info("DRY-RUN refresh_features", extra={"incident": incident.get("incident_id")})
        return {"action": "refresh_features", "status": "dry_run"}

    try:
        from google.cloud import scheduler_v1
        from src.utils.config import get_config
        cfg = get_config()
        c = scheduler_v1.CloudSchedulerClient()
        name = f"projects/{cfg.project_id}/locations/{cfg.region}/jobs/{cfg.name_prefix}-victim-retrain"
        c.run_job(name=name)
        return {"action": "refresh_features", "status": "applied", "job": name}
    except Exception as e:
        return {"action": "refresh_features", "status": "error", "error": str(e)}


def disable_endpoint(incident: dict) -> dict:
    """Emergency-stop — log only by default; real action requires approval."""
    log.warning("emergency disable_endpoint requested", extra={"incident": incident.get("incident_id")})
    return {"action": "disable_endpoint", "status": "approval_required"}


ACTION_REGISTRY = {
    "rollback_model": rollback_model,
    "scale_pods": scale_pods,
    "refresh_features": refresh_features,
    "disable_endpoint": disable_endpoint,
}


def execute(runbook_id: str, incident: dict) -> dict:
    fn = ACTION_REGISTRY.get(runbook_id)
    if fn is None:
        return {"action": runbook_id, "status": "unknown_runbook"}
    return fn(incident)
