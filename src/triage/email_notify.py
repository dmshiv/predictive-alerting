"""
============================================================
WHAT  : Email fallback for alert delivery.
WHY   : Slack is optional. Email always works because Cloud
        Monitoring's email channel handles delivery.
HOW   : We write a row to BigQuery `incidents` (always) and
        rely on Cloud Monitoring alert policies (set up in
        17-monitoring) to email on log-metric breaches.
NOTE  : This is a stub — actual email sending is delegated
        to Cloud Monitoring notification channels, configured
        in 17-monitoring/notification-channels.tf.
============================================================
"""
from __future__ import annotations

import logging

log = logging.getLogger(__name__)


class EmailNotifier:
    """Marker class — emits a structured log Cloud Monitoring
    converts into an alert via the log-based metric."""

    def post(self, incident: dict, report: str) -> bool:
        log.warning(
            "email-bound predictive alert",
            extra={
                "event": "predictive_alert",        # picked up by 17-monitoring log-metric
                "incident_id": incident.get("incident_id"),
                "metric_name": incident.get("metric_name"),
                "severity": incident.get("severity"),
                "report_excerpt": report[:300],
            },
        )
        return True
