"""
============================================================
WHAT  : Posts incident reports to Slack via webhook.
WHY   : Slack is where on-calls live.
HOW   : Reads the webhook URL from Secret Manager. If the
        secret is missing/placeholder, silently no-ops.
============================================================
"""
from __future__ import annotations

import logging

import requests

from src.utils.config import get_config
from src.utils.secret_client import Secrets

log = logging.getLogger(__name__)


class SlackNotifier:
    def __init__(self):
        cfg = get_config()
        self.cfg = cfg
        self.secrets = Secrets(cfg.project_id)

    def _webhook(self) -> str:
        url = self.secrets.get(self.cfg.secret_slack_webhook)
        if url and url != "PLACEHOLDER_OVERWRITE_ME":
            return url
        return ""

    def post(self, incident: dict, report: str, runbook: dict | None) -> bool:
        url = self._webhook()
        if not url:
            log.info("slack webhook not configured; skipping")
            return False

        metric = incident.get("metric_name", "unknown")
        severity = incident.get("severity", "medium").upper()
        lead = incident.get("lead_time_minutes", "?")

        blocks = [
            {"type": "header", "text": {"type": "plain_text", "text": f"🚨 Sentinel Predictive Alert · {severity}"}},
            {"type": "section", "fields": [
                {"type": "mrkdwn", "text": f"*Metric*\n`{metric}`"},
                {"type": "mrkdwn", "text": f"*Lead time*\n{lead} min"},
            ]},
            {"type": "section", "text": {"type": "mrkdwn", "text": report[:2900]}},
        ]
        if runbook:
            blocks.append({
                "type": "section",
                "text": {"type": "mrkdwn", "text": f"*Recommended runbook:* `{runbook.get('runbook_id')}` — {runbook.get('title')}"},
            })

        try:
            r = requests.post(url, json={"blocks": blocks}, timeout=5)
            r.raise_for_status()
            return True
        except Exception:
            log.exception("slack post failed")
            return False
