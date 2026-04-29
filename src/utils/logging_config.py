"""
============================================================
WHAT  : Structured JSON logger. Cloud Logging picks up severity
        + extra fields automatically when logs are JSON.
WHY   : So we can filter "show me every Gemini call" or
        "every predictive_alert event" trivially in console.
HOW   : Python logging Formatter that emits JSON.
LAYMAN: Instead of plain text "ERROR: bad thing", we emit
        {"severity": "ERROR", "message": "bad thing", ...}
        which Cloud Logging can index and search.
============================================================
"""
from __future__ import annotations

import json
import logging
import sys
from datetime import datetime, timezone


class JsonFormatter(logging.Formatter):
    """Render every log line as a one-line JSON object."""

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "severity": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
        }
        # If the caller passed extra={"event": "...", "endpoint_id": "..."},
        # surface those as top-level keys for easy Cloud Logging filtering.
        for key, value in record.__dict__.items():
            if key in ("args", "msg", "levelname", "levelno", "pathname",
                      "filename", "module", "exc_info", "exc_text", "stack_info",
                      "lineno", "funcName", "created", "msecs", "relativeCreated",
                      "thread", "threadName", "processName", "process", "name", "message"):
                continue
            payload[key] = value

        if record.exc_info:
            payload["exc_info"] = self.formatException(record.exc_info)

        return json.dumps(payload, default=str)


def setup_logging(level: str = "INFO") -> logging.Logger:
    """Configure root logger to emit JSON to stdout. Call once at app start."""
    root = logging.getLogger()
    root.setLevel(level)
    # Replace any existing handlers (avoid duplicate logs in containers)
    for h in list(root.handlers):
        root.removeHandler(h)

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root.addHandler(handler)
    return root
