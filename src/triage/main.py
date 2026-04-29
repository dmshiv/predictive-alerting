"""
============================================================
WHAT  : The Cloud Run triage service.
WHY   : This is THE central nervous system when an alert
        fires — Pub/Sub pushes here, Gemini writes the
        report, RecSys picks the runbook, auto-remediate
        executes (dry-run by default), Slack/email notify,
        BigQuery records the incident.
HOW   : FastAPI app with /alert (Pub/Sub push) and /healthz.
============================================================
"""
from __future__ import annotations

import base64
import json
import logging
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request

from src.runbook_recommender.recommender import RunbookRecommender, load_runbook_library
from src.triage.auto_remediate import execute as auto_execute
from src.triage.email_notify import EmailNotifier
from src.triage.gemini_triage import GeminiTriage
from src.triage.incident_writer import IncidentWriter
from src.triage.slack_notify import SlackNotifier
from src.utils.logging_config import setup_logging

setup_logging()
log = logging.getLogger(__name__)

# Load the runbook library at boot
RUNBOOK_DIR = Path(__file__).resolve().parent.parent / "runbook_recommender" / "runbooks"
RUNBOOKS = load_runbook_library(RUNBOOK_DIR)
RECOMMENDER = RunbookRecommender(RUNBOOKS)
GEMINI = GeminiTriage()
SLACK = SlackNotifier()
EMAIL = EmailNotifier()
INCIDENT_WRITER = IncidentWriter()

app = FastAPI(title="Sentinel Triage")


@app.get("/healthz")
def healthz():
    return {
        "ok": True,
        "n_runbooks": len(RUNBOOKS),
        "gemini_configured": GEMINI._configure(),
    }


@app.post("/alert")
async def alert(request: Request):
    """Pub/Sub push endpoint. Body wraps the actual incident in `message.data`."""
    body = await request.json()
    msg = body.get("message", {})
    raw = msg.get("data", "")
    try:
        decoded = base64.b64decode(raw).decode("utf-8")
        incident = json.loads(decoded)
    except Exception:
        # Direct invocation (curl) — accept the body as the incident
        incident = body

    if not incident or "incident_id" not in incident:
        raise HTTPException(status_code=400, detail="missing incident payload")

    log.info("alert received", extra={"event": "alert_received", "incident_id": incident["incident_id"]})

    # 1. Gemini writes the report
    report = GEMINI.write_report(incident, log_clusters=None)

    # 2. RecSys picks runbook(s)
    rec = RECOMMENDER.recommend({
        "metric_name": incident.get("metric_name", ""),
        "severity": incident.get("severity", "medium"),
    }, k=1)
    runbook_id = rec[0][0] if rec else None
    runbook = RUNBOOKS.get(runbook_id) if runbook_id else None

    # 3. Auto-remediate (dry-run unless AUTO_REMEDIATE=true)
    remediation = auto_execute(runbook_id, incident) if runbook_id else None

    # 4. Notify (Slack + email always; either may no-op)
    runbook_dict = (
        {"runbook_id": runbook.runbook_id, "title": runbook.title} if runbook else None
    )
    SLACK.post(incident, report, runbook_dict)
    EMAIL.post(incident, report)

    # 5. Persist
    INCIDENT_WRITER.write(incident, report, runbook_id, remediation)

    return {
        "ok": True,
        "incident_id": incident["incident_id"],
        "runbook_id": runbook_id,
        "remediation_status": remediation.get("status") if remediation else None,
    }
