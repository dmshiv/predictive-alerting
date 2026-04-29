"""
============================================================
WHAT  : Persists every incident to BigQuery `incidents`.
WHY   : So the runbook RecSys can train on history, and the
        TSE has a queryable audit log.
============================================================
"""
from __future__ import annotations

import json
import logging
from datetime import datetime, timezone

from src.utils.bq_client import BQ
from src.utils.config import get_config

log = logging.getLogger(__name__)


class IncidentWriter:
    def __init__(self):
        cfg = get_config()
        self.cfg = cfg
        self.bq = BQ(cfg.project_id)

    def write(self, incident: dict, report: str, runbook_id: str | None, remediation: dict | None) -> None:
        # BigQuery JSON columns must be passed as JSON-serialized strings to
        # insert_rows_json (passing a raw dict makes the streaming insert fail
        # with "Cannot convert struct field ... to JSON").
        ff = incident.get("feature_fingerprint")
        if ff is not None and not isinstance(ff, str):
            ff = json.dumps(ff, default=str)

        row = {
            "incident_id": incident.get("incident_id"),
            "fired_at": incident.get("fired_at") or datetime.now(timezone.utc).isoformat(),
            "predicted_breach_at": incident.get("predicted_breach_at"),
            "endpoint_id": incident.get("endpoint_id"),
            "metric_name": incident.get("metric_name"),
            "severity": incident.get("severity"),
            "gemini_report": report,
            "runbook_id": runbook_id,
            "remediation": json.dumps(remediation) if remediation else None,
            "feature_fingerprint": ff,
        }
        try:
            self.bq.insert_rows(self.cfg.bq_incidents_table, [row])
            log.info("incident persisted", extra={"event": "incident_written", "incident_id": row["incident_id"]})
        except Exception:
            # Don't swallow silently — re-log row keys so we can debug from Cloud Logging.
            log.exception("incident write failed", extra={"row_keys": list(row.keys()), "incident_id": row["incident_id"]})
