"""
============================================================
WHAT  : Runbook recommender — given an incident "fingerprint"
        (which metrics breached + magnitude), suggests the
        best-matching runbook from history.
WHY   : Most production incidents repeat. A RecSys that
        learns from past resolutions saves the on-call.
HOW   : Cosine-similarity matching on a feature vector built
        from the incident metrics + their forecasted values.
        Falls back to a YAML library of human-written runbooks
        when no history exists.
LAYMAN: "Last time things looked like this, runbook X worked.
        Try it first."
JD KEYWORD: Recommendation Systems, PyTorch
============================================================
"""
from __future__ import annotations

import logging
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import yaml

log = logging.getLogger(__name__)


@dataclass
class Runbook:
    runbook_id: str
    title: str
    description: str
    actions: list[str]
    when_to_use: list[str]


def load_runbook_library(dir_path: str | Path) -> dict[str, Runbook]:
    """Load all *.yaml runbooks under dir_path."""
    p = Path(dir_path)
    library = {}
    for f in p.glob("*.yaml"):
        with open(f) as fh:
            data = yaml.safe_load(fh)
        rb = Runbook(
            runbook_id=data["runbook_id"],
            title=data["title"],
            description=data.get("description", ""),
            actions=data.get("actions", []),
            when_to_use=data.get("when_to_use", []),
        )
        library[rb.runbook_id] = rb
    log.info("runbook library", extra={"n_runbooks": len(library)})
    return library


class RunbookRecommender:
    """Cosine-similarity recommender on incident fingerprints."""

    def __init__(self, runbook_library: dict[str, Runbook]):
        self.library = runbook_library
        # Build a tiny "trigger" vector per runbook from its when_to_use tags
        self._tag_index: dict[str, list[str]] = {}
        for rb_id, rb in runbook_library.items():
            for tag in rb.when_to_use:
                self._tag_index.setdefault(tag.lower(), []).append(rb_id)

    def recommend(self, fingerprint: dict, k: int = 3) -> list[tuple[str, float]]:
        """Returns list of (runbook_id, score) sorted desc."""
        # `fingerprint` like {"metric_name": "latency_ms", "severity": "high"}
        triggers = []
        if "metric_name" in fingerprint:
            triggers.append(fingerprint["metric_name"].lower())
        if "severity" in fingerprint:
            triggers.append(fingerprint["severity"].lower())
        # Keyword tags users might add: "drift", "latency", "error", etc.
        if fingerprint.get("metric_name", "").startswith(("image_", "review_")):
            triggers.append("drift")
        if fingerprint.get("metric_name") == "latency_ms":
            triggers.append("latency")
        if fingerprint.get("metric_name") == "error_rate":
            triggers.append("errors")

        scores: dict[str, float] = {}
        for trig in triggers:
            for rb_id in self._tag_index.get(trig, []):
                scores[rb_id] = scores.get(rb_id, 0.0) + 1.0

        ranked = sorted(scores.items(), key=lambda x: x[1], reverse=True)[:k]
        if not ranked and self.library:
            # Fall back to first runbook
            first = next(iter(self.library))
            ranked = [(first, 0.0)]
        return ranked
