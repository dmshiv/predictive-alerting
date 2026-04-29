"""
============================================================
WHAT  : Gemini-powered triage report writer.
WHY   : When a predictive alert fires, we want a human-
        readable explanation, not raw numbers. Gemini turns
        "image_embedding_norm crossed 1.20" into "input
        photo distribution shifted; likely cause: user-
        uploaded selfies replacing studio shots."
HOW   : Build a structured prompt -> call Gemini API ->
        return the report text.
LAYMAN: The on-call's robot scribe.
JD KEYWORD: Gemini, Generative AI
============================================================
"""
from __future__ import annotations

import logging
import os

from src.utils.config import get_config
from src.utils.secret_client import Secrets

log = logging.getLogger(__name__)


_PROMPT_TEMPLATE = """You are a senior SRE/ML engineer triaging a PRODUCTION ML incident.
A predictive-alerting system has forecasted an SLO breach BEFORE it happened.
Write a concise (max 6 sentences) root-cause hypothesis + recommended next step.

Incident facts:
- Metric forecasted to breach: {metric_name}
- Severity: {severity}
- Predicted breach in: {lead_time_minutes} minutes
- Operator and threshold: {operator} {threshold}
- Predicted peak value: {predicted_peak}
- Recent feature stats (last 5 min): {feature_stats}
- Recent log clusters (top 3 error patterns): {log_clusters}

Write in plain English, suitable for a Slack message. Start with the most
likely cause in bold. Avoid hedging language. End with one concrete action."""


class GeminiTriage:
    def __init__(self):
        self.cfg = get_config()
        self.secrets = Secrets(self.cfg.project_id)
        self._configured = False

    def _configure(self) -> bool:
        if self._configured:
            return True
        try:
            import google.generativeai as genai
            api_key = self.secrets.get(self.cfg.secret_gemini_key)
            if not api_key or api_key == "PLACEHOLDER_OVERWRITE_ME":
                log.warning("Gemini key not configured; using fallback summarizer")
                return False
            genai.configure(api_key=api_key)
            self._client = genai.GenerativeModel("gemini-1.5-flash")
            self._configured = True
            return True
        except Exception:
            log.exception("Gemini configure failed")
            return False

    def write_report(self, incident: dict, log_clusters: list[dict] | None = None) -> str:
        """Returns a Slack-ready string."""
        prompt = _PROMPT_TEMPLATE.format(
            metric_name=incident.get("metric_name", "unknown"),
            severity=incident.get("severity", "medium"),
            lead_time_minutes=incident.get("lead_time_minutes", "?"),
            operator=incident.get("operator", "?"),
            threshold=incident.get("threshold", "?"),
            predicted_peak=incident.get("predicted_peak", "?"),
            feature_stats=incident.get("feature_fingerprint", {}),
            log_clusters=log_clusters or [],
        )

        if not self._configure():
            return self._fallback(incident, log_clusters)

        try:
            log.info("calling Gemini", extra={"event": "gemini_call"})
            resp = self._client.generate_content(prompt)
            return resp.text.strip() if resp.text else self._fallback(incident, log_clusters)
        except Exception:
            log.exception("Gemini call failed")
            return self._fallback(incident, log_clusters)

    def _fallback(self, incident: dict, log_clusters: list[dict] | None) -> str:
        """Deterministic fallback when Gemini is unavailable."""
        metric = incident.get("metric_name", "unknown")
        lead = incident.get("lead_time_minutes", "?")
        peak = incident.get("predicted_peak", "?")
        cluster_str = (
            f"Top error cluster: {log_clusters[0].get('exemplar', '')[:80]}..."
            if log_clusters
            else "No new error patterns detected."
        )
        return (
            f"**Likely cause: distribution shift on `{metric}`.** "
            f"Forecast shows breach in ~{lead} min (peak ~{peak}). "
            f"{cluster_str} "
            f"Recommended next step: review the runbook below and consider rolling back."
        )
